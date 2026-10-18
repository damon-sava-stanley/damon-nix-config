#!/usr/bin/env python3
"""Print the battery levels exposed by a connected KBHTotem."""

import json
import re
import subprocess
import sys


DEVICE_NAME = "KBHTotem"
BATTERY_SERVICE_UUID = "0000180f-0000-1000-8000-00805f9b34fb"
BATTERY_LEVEL_UUID = "00002a19-0000-1000-8000-00805f9b34fb"
USER_DESCRIPTION_UUID = "00002901-0000-1000-8000-00805f9b34fb"


def busctl(*arguments: str, json_output: bool = True) -> object:
    command = ["busctl", "--system"]
    if json_output:
        command.append("--json=short")
    command.extend(arguments)

    try:
        result = subprocess.run(
            command, check=True, capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        raise RuntimeError(detail.strip()) from error
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("timed out querying Bluetooth") from error

    if json_output:
        return json.loads(result.stdout)
    return result.stdout


def property_value(path: str, interface: str, name: str) -> object:
    response = busctl("get-property", "org.bluez", path, interface, name)
    return response["data"]


def read_bytes(path: str, interface: str) -> list[int]:
    response = busctl("call", "org.bluez", path, interface, "ReadValue", "a{sv}", "0")
    if response.get("type") != "ay" or len(response.get("data", [])) != 1:
        raise RuntimeError(f"unexpected Bluetooth value from {path}")
    return response["data"][0]


def children(paths: list[str], parent: str, kind: str) -> list[str]:
    pattern = re.compile(re.escape(parent) + rf"/{kind}[0-9a-fA-F]+$")
    return [path for path in paths if pattern.fullmatch(path)]


def battery_levels() -> tuple[int, int]:
    paths = busctl("tree", "--list", "org.bluez", json_output=False).splitlines()
    device_pattern = re.compile(r"/org/bluez/hci[0-9]+/dev_[0-9a-fA-F_]+$")
    devices = [path for path in paths if device_pattern.fullmatch(path)]
    connected = [
        path
        for path in devices
        if property_value(path, "org.bluez.Device1", "Name") == DEVICE_NAME
        and property_value(path, "org.bluez.Device1", "Connected")
    ]
    if len(connected) != 1:
        raise RuntimeError(
            f"expected one connected {DEVICE_NAME}, found {len(connected)}"
        )

    levels: dict[str, int] = {}
    for service in children(paths, connected[0], "service"):
        if property_value(service, "org.bluez.GattService1", "UUID").lower() != BATTERY_SERVICE_UUID:
            continue

        for characteristic in children(paths, service, "char"):
            if property_value(characteristic, "org.bluez.GattCharacteristic1", "UUID").lower() != BATTERY_LEVEL_UUID:
                continue

            side = "Left"
            for descriptor in children(paths, characteristic, "desc"):
                if property_value(descriptor, "org.bluez.GattDescriptor1", "UUID").lower() == USER_DESCRIPTION_UUID:
                    description = bytes(
                        read_bytes(descriptor, "org.bluez.GattDescriptor1")
                    ).decode("utf-8")
                    if description.startswith("Peripheral "):
                        side = "Right"

            value = read_bytes(characteristic, "org.bluez.GattCharacteristic1")
            if len(value) != 1 or not 0 <= value[0] <= 100:
                raise RuntimeError(f"invalid {side.lower()} battery level: {value}")
            levels[side] = value[0]

    if set(levels) != {"Left", "Right"}:
        raise RuntimeError("both Totem battery services are not available")
    return levels["Left"], levels["Right"]


def main() -> int:
    try:
        left, right = battery_levels()
    except (RuntimeError, KeyError, TypeError, ValueError) as error:
        print(f"totem-battery: {error}", file=sys.stderr)
        return 1

    print(f"Left:  {left}%")
    print(f"Right: {right}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
