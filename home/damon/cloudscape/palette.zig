const std = @import("std");

/// A deliberately small control interface: an atomically replaced text file.
/// Missing/invalid values retain the last valid target. No animation-clock edits.
pub const Palette = struct {
    path: ?[]const u8 = null,
    current: f32 = 0,
    target: f32 = 0,
    until_poll: f32 = 0,

    pub fn init(path: ?[]const u8) Palette {
        var self = Palette{ .path = path };
        self.poll();
        self.current = self.target;
        return self;
    }

    fn poll(self: *Palette) void {
        const path = self.path orelse return;
        const file = std.fs.cwd().openFile(path, .{}) catch return;
        defer file.close();
        var buffer: [32]u8 = undefined;
        const len = file.readAll(&buffer) catch return;
        if (parse(buffer[0..len])) |value| self.target = value;
    }

    pub fn update(self: *Palette, elapsed: f32) f32 {
        // Support normal 1–120 fps frames; only long interruptions need a
        // gentle resume. Poll against wall time, not the capped blend step.
        const dt = if (elapsed > 2) 0.1 else @max(elapsed, 0);
        self.until_poll -= @max(elapsed, 0);
        if (self.until_poll <= 0) {
            self.poll();
            self.until_poll = 0.25;
        }
        self.current = blend(self.current, self.target, dt);
        return self.current;
    }
};

fn parse(text: []const u8) ?f32 {
    const mode = std.mem.trim(u8, text, " \t\r\n");
    if (std.mem.eql(u8, mode, "dark")) return 1;
    if (std.mem.eql(u8, mode, "light")) return 0;
    return null;
}

fn blend(current: f32, target: f32, dt: f32) f32 {
    const next = current + (target - current) * (1 - @exp(-dt / 0.8));
    return if (@abs(next - target) < 0.001) target else next;
}

test "only complete palette names are accepted" {
    try std.testing.expectEqual(@as(?f32, 1), parse("dark\n"));
    try std.testing.expectEqual(@as(?f32, 0), parse(" light \n"));
    try std.testing.expectEqual(@as(?f32, null), parse(""));
    try std.testing.expectEqual(@as(?f32, null), parse("dar"));
    try std.testing.expectEqual(@as(?f32, null), parse("dark garbage"));
}

test "blend is continuous, reversible, bounded, and settles" {
    var value: f32 = 0;
    for (0..30) |_| value = blend(value, 1, 1.0 / 30.0);
    try std.testing.expect(value > 0 and value < 1);
    const previous = value;
    value = blend(value, 0, 1.0 / 30.0);
    try std.testing.expect(value > 0 and value < previous);
    for (0..300) |_| value = blend(value, 0, 1.0 / 30.0);
    try std.testing.expectEqual(@as(f32, 0), value);
}

test "one fps still blends at wall-clock speed; long interruptions resume gently" {
    var palette = Palette{ .target = 1 };
    const after_second = palette.update(1);
    try std.testing.expect(after_second > 0.7 and after_second < 0.8);
    palette.current = 0;
    const after_resume = palette.update(60);
    try std.testing.expect(after_resume > 0 and after_resume < 0.2);
}

test "file updates preserve last valid target and initialize without a flash" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(.{ .sub_path = "palette", .data = "dark\n" });
    const path = try dir.dir.realpathAlloc(std.testing.allocator, "palette");
    defer std.testing.allocator.free(path);
    var palette = Palette.init(path);
    try std.testing.expectEqual(@as(f32, 1), palette.current);
    try dir.dir.writeFile(.{ .sub_path = "palette", .data = "light\n" });
    const value = palette.update(0.033);
    try std.testing.expect(value > 0 and value < 1);
    try std.testing.expectEqual(@as(f32, 0), palette.target);
    try dir.dir.writeFile(.{ .sub_path = "palette", .data = "invalid\n" });
    palette.until_poll = 0;
    _ = palette.update(0.033);
    try std.testing.expectEqual(@as(f32, 0), palette.target);
    try dir.dir.deleteFile("palette");
    palette.until_poll = 0;
    _ = palette.update(0.033);
    try std.testing.expectEqual(@as(f32, 0), palette.target);
}
