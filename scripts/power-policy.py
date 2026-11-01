"""AC-aware idle sleep. Lid position is deliberately ignored."""
import argparse
import subprocess
import time


def on_ac():
    result = subprocess.run(['systemd-ac-power'], check=False).returncode
    return {0: True, 1: False}.get(result)


def wait_for_battery():
    # Run in a user service that swayidle stops on activity. This also catches
    # unplugging after the idle timeout has already fired on AC.
    while on_ac() is not False:
        time.sleep(2)
    subprocess.run(['systemctl', 'suspend-then-hibernate'], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--idle-wait', action='store_true', required=True,
                        help='wait for battery, then suspend; cancelled by swayidle on activity')
    parser.parse_args()
    wait_for_battery()


if __name__ == '__main__':
    main()
