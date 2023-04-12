const cairo = @import("cairo-1.0");

// TODO: there should be some way to generate most of this

pub fn Context(comptime Self: type) type {
    return struct {
        extern fn cairo_create(target: *cairo.Surface) *Self;
        pub const create = cairo_create;
    };
}

pub fn ContextMethods(comptime Self: type) type {
    return struct {
        extern fn cairo_reference(cr: *Self) *Self;
        pub const reference = cairo_reference;

        extern fn cairo_destroy(cr: *Self) void;
        pub const destroy = cairo_destroy;

        extern fn cairo_status(cr: *Self) cairo.Status;
        pub const status = cairo_status;

        extern fn cairo_save(cr: *Self) void;
        pub const save = cairo_save;

        extern fn cairo_restore(cr: *Self) void;
        pub const restore = cairo_restore;

        extern fn cairo_get_target(cr: *Self) *cairo.Surface;
        pub const getTarget = cairo_get_target;

        extern fn cairo_push_group(cr: *Self) void;
        pub const pushGroup = cairo_push_group;

        extern fn cairo_push_group_with_content(cr: *Self, content: cairo.Content) void;
        pub const pushGroupWithContent = cairo_push_group_with_content;

        extern fn cairo_pop_group(cr: *Self) *cairo.Pattern;
        pub const popGroup = cairo_pop_group;

        extern fn cairo_pop_group_to_source(cr: *Self) void;
        pub const popGroupToSource = cairo_pop_group_to_source;

        extern fn cairo_get_group_target(cr: *Self) *cairo.Surface;
        pub const getGroupTarget = cairo_get_group_target;

        extern fn cairo_set_source_rgb(cr: *Self, red: f64, green: f64, blue: f64) void;
        pub const setSourceRgb = cairo_set_source_rgb;

        extern fn cairo_set_source_rgba(cr: *Self, red: f64, green: f64, blue: f64, alpha: f64) void;
        pub const setSourceRgba = cairo_set_source_rgba;

        extern fn cairo_set_source(cr: *Self, source: *cairo.Pattern) void;
        pub const setSource = cairo_set_source;

        extern fn cairo_set_source_surface(cr: *Self, surface: *cairo.Surface, x: f64, y: f64) void;
        pub const setSourceSurface = cairo_set_source_surface;

        extern fn cairo_get_source(cr: *Self) *cairo.Pattern;
        pub const getSource = cairo_get_source;

        extern fn cairo_set_antialias(cr: *Self, antialias: cairo.Antialias) void;
        pub const setAntialias = cairo_set_antialias;

        extern fn cairo_get_antialias(cr: *Self) cairo.Antialias;
        pub const getAntialias = cairo_get_antialias;

        extern fn cairo_set_dash(cr: *Self, dashes: [*]const f64, num_dashes: c_int, offset: f64) void;
        pub const setDash = cairo_set_dash;

        extern fn cairo_get_dash_count(cr: *Self) c_int;
        pub const getDashCount = cairo_get_dash_count;

        extern fn cairo_get_dash(cr: *Self, dashes: ?*f64, offset: ?*f64) c_int;
        pub const getDash = cairo_get_dash;

        extern fn cairo_set_fill_rule(cr: *Self, cr: cairo.FillRule) void;
        pub const setFillRule = cairo_set_fill_rule;

        extern fn cairo_get_fill_rule(cr: *Self) cairo.FillRule;
        pub const getFillRule = cairo_get_fill_rule;

        extern fn cairo_set_line_cap(cr: *Self, line_cap: cairo.LineCap) void;
        pub const setLineCap = cairo_set_line_cap;

        extern fn cairo_get_line_cap(cr: *Self) cairo.LineCap;
        pub const getLineCap = cairo_get_line_cap;

        extern fn cairo_set_line_join(cr: *Self, line_join: cairo.LineJoin) void;
        pub const setLineJoin = cairo_set_line_join;

        extern fn cairo_get_line_join(cr: *Self) cairo.LineJoin;
        pub const getLineJoin = cairo_get_line_join;

        extern fn cairo_set_line_width(cr: *Self, line_width: f64) void;
        pub const setLineWidth = cairo_set_line_width;

        extern fn cairo_get_line_width(cr: *Self) f64;
        pub const getLineWidth = cairo_get_line_width;

        extern fn cairo_set_miter_limit(cr: *Self, miter_limit: f64) void;
        pub const setMiterLimit = cairo_set_miter_limit;

        extern fn cairo_get_miter_limit(cr: *Self) f64;
        pub const getMiterLimit = cairo_get_miter_limit;

        extern fn cairo_set_operator(cr: *Self, operator: cairo.Operator) void;
        pub const setOperator = cairo_set_operator;

        extern fn cairo_get_operator(cr: *Self) cairo.Operator;
        pub const getOperator = cairo_get_operator;

        extern fn cairo_set_tolerance(cr: *Self, tolerance: f64) void;
        pub const setTolerance = cairo_set_tolerance;

        extern fn cairo_get_tolerance(cr: *Self) f64;
        pub const getTolerance = cairo_get_tolerance;

        extern fn cairo_clip(cr: *Self) void;
        pub const clip = cairo_clip;

        extern fn cairo_clip_preserve(cr: *Self) void;
        pub const clipPreserve = cairo_clip_preserve;

        extern fn cairo_clip_extents(cr: *Self, x1: *f64, y1: *f64, x2: *f64, y2: *f64) void;
        pub const clipExtents = cairo_clip_extents;

        extern fn cairo_in_clip(cr: *Self, x: f64, y: f64) bool;
        pub const inClip = cairo_in_clip;

        extern fn cairo_reset_clip(cr: *Self) void;
        pub const resetClip = cairo_reset_clip;

        extern fn cairo_fill(cr: *Self) void;
        pub const fill = cairo_fill;

        extern fn cairo_fill_preserve(cr: *Self) void;
        pub const fillPreserve = cairo_fill_preserve;

        extern fn cairo_fill_extents(cr: *Self, x1: *f64, y1: *f64, x2: *f64, y2: *f64) void;
        pub const fillExtents = cairo_fill_extents;

        extern fn cairo_in_fill(cr: *Self, x: f64, y: f64) bool;
        pub const inFill = cairo_in_fill;

        extern fn cairo_mask(cr: *Self, pattern: *cairo.Pattern) void;
        pub const mask = cairo_mask;

        extern fn cairo_mask_surface(cr: *Self, surface: *cairo.Surface, surface_x: f64, surface_y: f64) void;
        pub const maskSurface = cairo_mask_surface;

        extern fn cairo_paint(cr: *Self) void;
        pub const paint = cairo_paint;

        extern fn cairo_paint_with_alpha(cr: *Self, alpha: f64) void;
        pub const paintWithAlpha = cairo_paint_with_alpha;

        extern fn cairo_stroke(cr: *Self) void;
        pub const stroke = cairo_stroke;

        extern fn cairo_stroke_preserve(cr: *Self) void;
        pub const strokePreserve = cairo_stroke_preserve;

        extern fn cairo_stroke_extents(cr: *Self, x1: *f64, y1: *f64, x2: *f64, y2: *f64) void;
        pub const strokeExtents = cairo_stroke_extents;

        extern fn cairo_in_stroke(cr: *Self, x: f64, y: f64) bool;
        pub const inStroke = cairo_in_stroke;

        extern fn cairo_copy_page(cr: *Self) void;
        pub const copyPage = cairo_copy_page;

        extern fn cairo_show_page(cr: *Self) void;
        pub const showPage = cairo_show_page;

        extern fn cairo_get_reference_count(cr: *Self) c_uint;
        pub const getReferenceCount = cairo_get_reference_count;

        extern fn cairo_new_path(cr: *Self) void;
        pub const newPath = cairo_new_path;

        extern fn cairo_line_to(cr: *Self, x: f64, y: f64) void;
        pub const lineTo = cairo_line_to;

        extern fn cairo_move_to(cr: *Self, x: f64, y: f64) void;
        pub const moveTo = cairo_move_to;

        extern fn cairo_translate(cr: *Self, x: f64, y: f64) void;
        pub const translate = cairo_translate;

        extern fn cairo_rotate(cr: *Self, angle: f64) void;
        pub const rotate = cairo_rotate;

        extern fn cairo_rectangle(cr: *Self, x: f64, y: f64, width: f64, height: f64) void;
        pub const rectangle = cairo_rectangle;
    };
}

pub fn SurfaceMethods(comptime Self: type) type {
    return struct {
        extern fn cairo_surface_destroy(surface: *Self) void;
        pub const destroy = cairo_surface_destroy;
    };
}
