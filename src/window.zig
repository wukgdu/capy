const std = @import("std");
const backend = @import("backend.zig");
const internal = @import("internal.zig");
const Widget = @import("widget.zig").Widget;
const ImageData = @import("image.zig").ImageData;
const MenuBar_Impl = @import("components/Menu.zig").MenuBar_Impl;
const Size = @import("data.zig").Size;
const Atom = @import("data.zig").Atom;

const Display = struct { resolution: Size, dpi: u32 };

const devices = std.ComptimeStringMap(Display, .{
    .{ "iphone-13-mini", .{ .resolution = Size.init(1080, 2340), .dpi = 476 } },
    .{ "iphone-13", .{ .resolution = Size.init(1170, 2532), .dpi = 460 } },
    .{ "pixel-6", .{ .resolution = Size.init(1080, 2400), .dpi = 411 } },
    .{ "pixel-6-pro", .{ .resolution = Size.init(1440, 3120), .dpi = 512 } },
});

pub const Window = struct {
    peer: backend.Window,
    _child: ?Widget = null,
    // TODO: make it call setPreferredSize, if resizing ended up doing a no-up then revert
    // 'size' to what it was before
    // TODO: maybe implement vetoable changes to make it work
    size: Atom(Size) = Atom(Size).of(Size.init(640, 480)),
    /// The maximum refresh rate of the screen the window is atleast partially in.
    /// For instance, if a window is on both screen A (60Hz) and B (144Hz) then the value of screenRefreshRate will be 144Hz.
    screenRefreshRate: Atom(f32) = Atom(f32).of(60),

    pub const Feature = enum {
        Title,
        Icon,
        MenuBar,
    };

    pub fn init() !Window {
        const peer = try backend.Window.create();
        var window = Window{ .peer = peer };
        window.setSourceDpi(96);
        window.setPreferredSize(640, 480);
        try window.peer.setCallback(.Resize, sizeChanged);

        return window;
    }

    pub fn show(self: *Window) void {
        self.peer.setUserData(self);
        return self.peer.show();
    }

    pub fn close(self: *Window) void {
        return self.peer.close();
    }

    fn isErrorUnion(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .ErrorUnion => true,
            else => false,
        };
    }

    /// wrappedContainer can be an error union, a pointer to the container or the container itself.
    pub inline fn set(self: *Window, wrappedContainer: anytype) anyerror!void {
        var container =
            if (comptime isErrorUnion(@TypeOf(wrappedContainer)))
            try wrappedContainer
        else
            wrappedContainer;
        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(container));

        self._child = try @import("internal.zig").genericWidgetFrom(container);
        if (ComponentType != Widget) {
            self._child.?.as(ComponentType).widget_data.atoms.widget = &self._child.?;
        }

        try self._child.?.show();

        self.peer.setChild(self._child.?.peer);
    }

    pub fn getChild(self: Window) ?Widget {
        return self._child;
    }

    var did_invalid_warning = false;
    /// Attempt to resize the window to the given size.
    /// On certain platforms (e.g. mobile) or configurations (e.g. tiling window manager) this function might do nothing.
    pub fn setPreferredSize(self: *Window, width: u32, height: u32) void {
        const EMULATOR_KEY = "CAPY_MOBILE_EMULATED";
        if (std.process.hasEnvVarConstant(EMULATOR_KEY)) {
            const id = std.process.getEnvVarOwned(internal.scratch_allocator, EMULATOR_KEY) catch unreachable;
            defer internal.scratch_allocator.free(id);
            if (devices.get(id)) |device| {
                self.peer.resize(@as(c_int, @intCast(device.resolution.width)), @as(c_int, @intCast(device.resolution.height)));
                self.setSourceDpi(device.dpi);
                return;
            } else if (!did_invalid_warning) {
                std.log.warn("Invalid property \"" ++ EMULATOR_KEY ++ "={s}\"", .{id});
                std.debug.print("Expected one of:\r\n", .{});
                for (devices.kvs) |entry| {
                    std.debug.print("    - {s}\r\n", .{entry.key});
                }
                did_invalid_warning = true;
            }
        }
        self.size.set(.{ .width = width, .height = height });
        self.peer.setUserData(self);
        self.peer.resize(@as(c_int, @intCast(width)), @as(c_int, @intCast(height)));
    }

    fn sizeChanged(width: u32, height: u32, data: usize) void {
        const self = @as(*Window, @ptrFromInt(data));
        self.size.set(.{ .width = width, .height = height });
    }

    // TODO: minimumSize and maximumSize

    pub fn hasFeature(self: *Window, feature: Window.Feature) void {
        _ = feature;
        _ = self;
        // TODO
        return true;
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        self.peer.setTitle(title);
    }

    pub fn setIcon(self: *Window, icon: *ImageData) void {
        self.peer.setIcon(icon.data.peer);
    }

    pub fn setIconName(self: *Window, name: [:0]const u8) void {
        self.peer.setIconName(name);
    }

    pub fn setMenuBar(self: *Window, bar: MenuBar_Impl) void {
        self.peer.setMenuBar(bar);
    }

    /// Specify for which DPI the GUI was developed against.
    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.peer.setSourceDpi(dpi);
    }

    pub fn deinit(self: *Window) void {
        if (self._child) |*child| {
            child.deinit();
        }
        self.peer.deinit();
    }
};
