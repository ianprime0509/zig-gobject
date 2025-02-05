extern fn cairo_version() c_int;
pub const version = cairo_version;

pub const DestroyFunc = *const fn (data: ?*anyopaque) callconv(.c) void;
pub const WriteFunc = *const fn (closure: ?*anyopaque, data: [*]const u8, length: c_uint) callconv(.c) Status;
pub const ReadFunc = *const fn (closure: ?*anyopaque, data: [*]u8, length: c_uint) callconv(.c) Status;

pub const Status = enum(c_int) {
    success,

    no_memory,
    invalid_restore,
    invalid_pop_group,
    no_current_point,
    invalid_matrix,
    invalid_status,
    null_pointer,
    invalid_string,
    invalid_path_data,
    read_error,
    write_error,
    surface_finished,
    surface_type_mismatch,
    pattern_type_mismatch,
    invalid_content,
    invalid_format,
    invalid_visual,
    file_not_found,
    invalid_dash,
    invalid_dsc_comment,
    invalid_index,
    clip_not_representable,
    temp_file_error,
    invalid_stride,
    font_type_mismatch,
    user_font_immutable,
    user_font_error,
    negative_count,
    invalid_clusters,
    invalid_slant,
    invalid_weight,
    invalid_size,
    user_font_not_implemented,
    device_type_mismatch,
    device_error,
    invalid_mesh_construction,
    device_finished,
    jbig2_global_missing,
    png_error,
    freetype_error,
    win32_gdi_error,
    tag_error,
    dwrite_error,
    svg_font_error,
    _,

    extern fn cairo_status_to_string(status: Status) [*:0]const u8;
    pub const toString = cairo_status_to_string;
};

pub const UserDataKey = extern struct {
    unused: c_int,
};

pub const RectangleInt = extern struct {
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
};

pub const Rectangle = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

pub const RectangleList = extern struct {
    status: Status,
    rectangles: [*]Rectangle,
    num_rectangles: c_int,

    extern fn cairo_rectangle_list_destroy(rectangle_list: *RectangleList) void;
    pub const destroy = cairo_rectangle_list_destroy;
};

pub const Matrix = extern struct {
    xx: f64,
    yx: f64,
    xy: f64,
    yy: f64,
    x0: f64,
    y0: f64,

    extern fn cairo_matrix_init(matrix: *Matrix, xx: f64, yx: f64, xy: f64, yy: f64, x0: f64, y0: f64) void;
    pub const init = cairo_matrix_init;

    extern fn cairo_matrix_init_identity(matrix: *Matrix) void;
    pub const initIdentity = cairo_matrix_init_identity;

    extern fn cairo_matrix_init_translate(matrix: *Matrix, tx: f64, ty: f64) void;
    pub const initTranslate = cairo_matrix_init_translate;

    extern fn cairo_matrix_init_scale(matrix: *Matrix, sx: f64, sy: f64) void;
    pub const initScale = cairo_matrix_init_scale;

    extern fn cairo_matrix_init_rotate(matrix: *Matrix, radians: f64) void;
    pub const initRotate = cairo_matrix_init_rotate;

    extern fn cairo_matrix_translate(matrix: *Matrix, tx: f64, ty: f64) void;
    pub const translate = cairo_matrix_translate;

    extern fn cairo_matrix_scale(matrix: *Matrix, sx: f64, sy: f64) void;
    pub const scale = cairo_matrix_scale;

    extern fn cairo_matrix_rotate(matrix: *Matrix, radians: f64) void;
    pub const rotate = cairo_matrix_rotate;

    extern fn cairo_matrix_invert(matrix: *Matrix) Status;
    pub const invert = cairo_matrix_invert;

    extern fn cairo_matrix_multiply(result: *Matrix, a: *const Matrix, b: *const Matrix) void;
    pub const multiply = cairo_matrix_multiply;

    extern fn cairo_matrix_transform_distance(matrix: *const Matrix, dx: *f64, dy: *f64) void;
    pub const transformDistance = cairo_matrix_transform_distance;

    extern fn cairo_matrix_transform_point(matrix: *const Matrix, x: *f64, y: *f64) void;
    pub const transformPoint = cairo_matrix_transform_point;
};

pub const Context = opaque {
    extern fn cairo_create(target: *Surface) *Context;
    pub const create = cairo_create;

    extern fn cairo_reference(cr: *Context) *Context;
    pub const reference = cairo_reference;

    extern fn cairo_destroy(cr: *Context) void;
    pub const destroy = cairo_destroy;

    extern fn cairo_get_reference_count(cr: *Context) c_uint;
    pub const getReferenceCount = cairo_get_reference_count;

    extern fn cairo_get_user_data(cr: *Context, key: *const UserDataKey) ?*anyopaque;
    pub const getUserData = cairo_get_user_data;

    extern fn cairo_set_user_data(cr: *Context, key: *const UserDataKey, user_data: ?*anyopaque, destroy: DestroyFunc) Status;
    pub const setUserData = cairo_set_user_data;

    extern fn cairo_save(cr: *Context) void;
    pub const save = cairo_save;

    extern fn cairo_restore(cr: *Context) void;
    pub const restore = cairo_restore;

    extern fn cairo_push_group(cr: *Context) void;
    pub const pushGroup = cairo_push_group;

    extern fn cairo_push_group_with_content(cr: *Context, content: Content) void;
    pub const pushGroupWithContent = cairo_push_group_with_content;

    extern fn cairo_pop_group(cr: *Context) *Pattern;
    pub const popGroup = cairo_pop_group;

    extern fn cairo_pop_group_to_source(cr: *Context) void;
    pub const popGroupToSource = cairo_pop_group_to_source;

    extern fn cairo_set_operator(cr: *Context, op: Operator) void;
    pub const setOperator = cairo_set_operator;

    extern fn cairo_set_source(cr: *Context, source: *Pattern) void;
    pub const setSource = cairo_set_source;

    extern fn cairo_set_source_rgb(cr: *Context, red: f64, green: f64, blue: f64) void;
    pub const setSourceRgb = cairo_set_source_rgb;

    extern fn cairo_set_source_rgba(cr: *Context, red: f64, green: f64, blue: f64, alpha: f64) void;
    pub const setSourceRgba = cairo_set_source_rgba;

    extern fn cairo_set_source_surface(cr: *Context, surface: *Surface, x: f64, y: f64) void;
    pub const setSourceSurface = cairo_set_source_surface;

    extern fn cairo_set_tolerance(cr: *Context, tolerance: f64) void;
    pub const setTolerance = cairo_set_tolerance;

    extern fn cairo_set_antialias(cr: *Context, antialias: Antialias) void;
    pub const setAntialias = cairo_set_antialias;

    extern fn cairo_set_fill_rule(cr: *Context, fill_rule: FillRule) void;
    pub const setFillRule = cairo_set_fill_rule;

    extern fn cairo_set_line_width(cr: *Context, width: f64) void;
    pub const setLineWidth = cairo_set_line_width;

    extern fn cairo_set_hairline(cr: *Context, set_hairline: c_int) void;
    pub const setHairline = cairo_set_hairline;

    extern fn cairo_set_line_cap(cr: *Context, line_cap: LineCap) void;
    pub const setLineCap = cairo_set_line_cap;

    extern fn cairo_set_line_join(cr: *Context, line_join: LineJoin) void;
    pub const setLineJoin = cairo_set_line_join;

    extern fn cairo_set_dash(cr: *Context, dashes: [*]const f64, num_dashes: c_int, offset: f64) void;
    pub const setDash = cairo_set_dash;

    extern fn cairo_set_miter_limit(cr: *Context, limit: f64) void;
    pub const setMiterLimit = cairo_set_miter_limit;

    extern fn cairo_translate(cr: *Context, tx: f64, ty: f64) void;
    pub const translate = cairo_translate;

    extern fn cairo_scale(cr: *Context, sx: f64, sy: f64) void;
    pub const scale = cairo_scale;

    extern fn cairo_rotate(cr: *Context, angle: f64) void;
    pub const rotate = cairo_rotate;

    extern fn cairo_transform(cr: *Context, matrix: *const Matrix) void;
    pub const transform = cairo_transform;

    extern fn cairo_set_matrix(cr: *Context, matrix: *const Matrix) void;
    pub const setMatrix = cairo_set_matrix;

    extern fn cairo_identity_matrix(cr: *Context) void;
    pub const identityMatrix = cairo_identity_matrix;

    extern fn cairo_user_to_device(cr: *Context, x: *f64, y: *f64) void;
    pub const userToDevice = cairo_user_to_device;

    extern fn cairo_user_to_device_distance(cr: *Context, dx: *f64, dy: *f64) void;
    pub const userToDeviceDistance = cairo_user_to_device_distance;

    extern fn cairo_device_to_user(cr: *Context, x: *f64, y: *f64) void;
    pub const deviceToUser = cairo_device_to_user;

    extern fn cairo_device_to_user_distance(cr: *Context, dx: *f64, dy: *f64) void;
    pub const deviceToUserDistance = cairo_device_to_user_distance;

    extern fn cairo_new_path(cr: *Context) void;
    pub const newPath = cairo_new_path;

    extern fn cairo_move_to(cr: *Context, x: f64, y: f64) void;
    pub const moveTo = cairo_move_to;

    extern fn cairo_new_sub_path(cr: *Context) void;
    pub const newSubPath = cairo_new_sub_path;

    extern fn cairo_line_to(cr: *Context, x: f64, y: f64) void;
    pub const lineTo = cairo_line_to;

    extern fn cairo_curve_to(cr: *Context, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64) void;
    pub const curveTo = cairo_curve_to;

    extern fn cairo_arc(cr: *Context, xc: f64, yc: f64, radius: f64, angle1: f64, angle2: f64) void;
    pub const arc = cairo_arc;

    extern fn cairo_arc_negative(cr: *Context, xc: f64, yc: f64, radius: f64, angle1: f64, angle2: f64) void;
    pub const arcNegative = cairo_arc_negative;

    extern fn cairo_rel_move_to(cr: *Context, dx: f64, dy: f64) void;
    pub const relMoveTo = cairo_rel_move_to;

    extern fn cairo_rel_line_to(cr: *Context, dx: f64, dy: f64) void;
    pub const relLineTo = cairo_rel_line_to;

    extern fn cairo_rel_curve_to(cr: *Context, dx1: f64, dy1: f64, dx2: f64, dy2: f64, dx3: f64, dy3: f64) void;
    pub const relCurveTo = cairo_rel_curve_to;

    extern fn cairo_rectangle(cr: *Context, x: f64, y: f64, width: f64, height: f64) void;
    pub const rectangle = cairo_rectangle;

    extern fn cairo_close_path(cr: *Context) void;
    pub const closePath = cairo_close_path;

    extern fn cairo_path_extents(cr: *Context, x1: *f64, y1: *f64, x2: *f64, y2: *f64) void;
    pub const pathExtents = cairo_path_extents;

    extern fn cairo_paint(cr: *Context) void;
    pub const paint = cairo_paint;

    extern fn cairo_paint_with_alpha(cr: *Context, alpha: f64) void;
    pub const paintWithAlpha = cairo_paint_with_alpha;

    extern fn cairo_mask(cr: *Context, pattern: *Pattern) void;
    pub const mask = cairo_mask;

    extern fn cairo_mask_surface(cr: *Context, surface: *Surface, surface_x: f64, surface_y: f64) void;
    pub const maskSurface = cairo_mask_surface;

    extern fn cairo_stroke(cr: *Context) void;
    pub const stroke = cairo_stroke;

    extern fn cairo_stroke_preserve(cr: *Context) void;
    pub const strokePreserve = cairo_stroke_preserve;

    extern fn cairo_fill(cr: *Context) void;
    pub const fill = cairo_fill;

    extern fn cairo_fill_preserve(cr: *Context) void;
    pub const fillPreserve = cairo_fill_preserve;

    extern fn cairo_copy_page(cr: *Context) void;
    pub const copyPage = cairo_copy_page;

    extern fn cairo_show_page(cr: *Context) void;
    pub const showPage = cairo_show_page;

    extern fn cairo_in_stroke(cr: *Context, x: f64, y: f64) c_int;
    pub const inStroke = cairo_in_stroke;

    extern fn cairo_in_fill(cr: *Context, x: f64, y: f64) c_int;
    pub const inFill = cairo_in_fill;

    extern fn cairo_in_clip(cr: *Context, x: f64, y: f64) c_int;
    pub const inClip = cairo_in_clip;

    extern fn cairo_stroke_extents(cr: *Context, x1: *f64, y1: *f64, x2: *f64, y2: *f64) void;
    pub const strokeExtents = cairo_stroke_extents;

    extern fn cairo_fill_extents(cr: *Context, x1: *f64, y1: *f64, x2: *f64, y2: *f64) void;
    pub const fillExtents = cairo_fill_extents;

    extern fn cairo_reset_clip(cr: *Context) void;
    pub const resetClip = cairo_reset_clip;

    extern fn cairo_clip(cr: *Context) void;
    pub const clip = cairo_clip;

    extern fn cairo_clip_preserve(cr: *Context) void;
    pub const clipPreserve = cairo_clip_preserve;

    extern fn cairo_clip_extents(cr: *Context, x1: *f64, y1: *f64, x2: *f64, y2: *f64) void;
    pub const clipExtents = cairo_clip_extents;

    extern fn cairo_copy_clip_rectangle_list(cr: *Context) *RectangleList;
    pub const copyClipRectangleList = cairo_copy_clip_rectangle_list;

    extern fn cairo_tag_begin(cr: *Context, tag_name: [*:0]const u8, attributes: [*:0]const u8) void;
    pub const tagBegin = cairo_tag_begin;

    extern fn cairo_tag_end(cr: *Context, tag_name: [*:0]const u8) void;
    pub const tagEnd = cairo_tag_end;

    extern fn cairo_select_font_face(cr: *Context, family: [*:0]const u8, slant: FontSlant, weight: FontWeight) void;
    pub const selectFontFace = cairo_select_font_face;

    extern fn cairo_set_font_size(cr: *Context, size: f64) void;
    pub const setFontSize = cairo_set_font_size;

    extern fn cairo_set_font_matrix(cr: *Context, matrix: *const Matrix) void;
    pub const setFontMatrix = cairo_set_font_matrix;

    extern fn cairo_get_font_matrix(cr: *Context, matrix: *Matrix) void;
    pub const getFontMatrix = cairo_get_font_matrix;

    extern fn cairo_set_font_options(cr: *Context, options: *const FontOptions) void;
    pub const setFontOptions = cairo_set_font_options;

    extern fn cairo_get_font_options(cr: *Context, options: *FontOptions) void;
    pub const getFontOptions = cairo_get_font_options;

    extern fn cairo_set_font_face(cr: *Context, font_face: *FontFace) void;
    pub const setFontFace = cairo_set_font_face;

    extern fn cairo_get_font_face(cr: *Context) *FontFace;
    pub const getFontFace = cairo_get_font_face;

    extern fn cairo_set_scaled_font(cr: *Context, scaled_font: *const ScaledFont) void;
    pub const setScaledFont = cairo_set_scaled_font;

    extern fn cairo_get_scaled_font(cr: *Context) *ScaledFont;
    pub const getScaledFont = cairo_get_scaled_font;

    extern fn cairo_show_text(cr: *Context, utf8: [*:0]const u8) void;
    pub const showText = cairo_show_text;

    extern fn cairo_show_glyphs(cr: *Context, glyphs: [*]const Glyph, num_glyphs: c_int) void;
    pub const showGlyphs = cairo_show_glyphs;

    extern fn cairo_show_text_glyphs(cr: *Context, utf8: [*]const u8, utf8_len: c_int, glyphs: [*]const Glyph, num_glyphs: c_int, clusters: [*]const TextCluster, num_clusters: c_int, cluster_flags: TextClusterFlags) void;
    pub const showTextGlyphs = cairo_show_text_glyphs;

    extern fn cairo_text_path(cr: *Context, utf8: [*:0]const u8) void;
    pub const textPath = cairo_text_path;

    extern fn cairo_glyph_path(cr: *Context, glyphs: [*]const Glyph, num_glyphs: c_int) void;
    pub const glyphPath = cairo_glyph_path;

    extern fn cairo_text_extents(cr: *Context, utf8: [*:0]const u8, extents: *TextExtents) void;
    pub const textExtents = cairo_text_extents;

    extern fn cairo_glyph_extents(cr: *Context, glyphs: [*]const Glyph, num_glyphs: c_int, extents: *TextExtents) void;
    pub const glyphExtents = cairo_glyph_extents;

    extern fn cairo_font_extents(cr: *Context, extents: *FontExtents) void;
    pub const fontExtents = cairo_font_extents;

    extern fn cairo_get_operator(cr: *Context) Operator;
    pub const getOperator = cairo_get_operator;

    extern fn cairo_get_source(cr: *Context) *Pattern;
    pub const getSource = cairo_get_source;

    extern fn cairo_get_tolerance(cr: *Context) f64;
    pub const getTolerance = cairo_get_tolerance;

    extern fn cairo_get_antialias(cr: *Context) Antialias;
    pub const getAntialias = cairo_get_antialias;

    extern fn cairo_get_current_point(cr: *Context, x: *f64, y: *f64) void;
    pub const getCurrentPoint = cairo_get_current_point;

    extern fn cairo_get_fill_rule(cr: *Context) FillRule;
    pub const getFillRule = cairo_get_fill_rule;

    extern fn cairo_get_line_width(cr: *Context) f64;
    pub const getLineWidth = cairo_get_line_width;

    extern fn cairo_get_hairline(cr: *Context) c_int;
    pub const getHairline = cairo_get_hairline;

    extern fn cairo_get_line_cap(cr: *Context) LineCap;
    pub const getLineCap = cairo_get_line_cap;

    extern fn cairo_get_line_join(cr: *Context) LineJoin;
    pub const getLineJoin = cairo_get_line_join;

    extern fn cairo_get_miter_limit(cr: *Context) f64;
    pub const getMiterLimit = cairo_get_miter_limit;

    extern fn cairo_get_dash_count(cr: *Context) c_int;
    pub const getDashCount = cairo_get_dash_count;

    extern fn cairo_get_dash(cr: *Context, dashes: ?[*]f64, offset: ?*f64) void;
    pub const getDash = cairo_get_dash;

    extern fn cairo_get_matrix(cr: *Context, matrix: *Matrix) void;
    pub const getMatrix = cairo_get_matrix;

    extern fn cairo_get_target(cr: *Context) *Surface;
    pub const getTarget = cairo_get_target;

    extern fn cairo_get_group_target(cr: *Context) *Surface;
    pub const getGroupTarget = cairo_get_group_target;

    extern fn cairo_copy_path(cr: *Context) *Path;
    pub const copyPath = cairo_copy_path;

    extern fn cairo_copy_path_flat(cr: *Context) *Path;
    pub const copyPathFlat = cairo_copy_path_flat;

    extern fn cairo_status(cr: *Context) Status;
    pub const status = cairo_status;
};

pub const Surface = opaque {
    extern fn cairo_surface_create_similar(other: *Surface, content: Content, width: c_int, height: c_int) *Surface;
    pub const createSimilar = cairo_surface_create_similar;

    extern fn cairo_surface_create_similar_image(other: *Surface, format: Format, width: c_int, height: c_int) *Surface;
    pub const createSimilarImage = cairo_surface_create_similar_image;

    extern fn cairo_surface_map_to_image(surface: *Surface, extents: ?*const RectangleInt) *Surface;
    pub const mapToImage = cairo_surface_map_to_image;

    extern fn cairo_surface_unmap_image(surface: *Surface, image: *Surface) void;
    pub const unmapImage = cairo_surface_unmap_image;

    extern fn cairo_surface_create_for_rectangle(target: *Surface, x: f64, y: f64, width: f64, height: f64) *Surface;
    pub const createForRectangle = cairo_surface_create_for_rectangle;

    extern fn cairo_surface_create_observer(target: *Surface, mode: SurfaceObserverMode) *Surface;
    pub const createObserver = cairo_surface_create_observer;

    extern fn cairo_surface_observer_add_paint_callback(abstract_surface: *Surface, func: SurfaceObserverCallback, data: ?*anyopaque) Status;
    pub const observerAddPaintCallback = cairo_surface_observer_add_paint_callback;

    extern fn cairo_surface_observer_add_mask_callback(abstract_surface: *Surface, func: SurfaceObserverCallback, data: ?*anyopaque) Status;
    pub const observerAddMaskCallback = cairo_surface_observer_add_mask_callback;

    extern fn cairo_surface_observer_add_fill_callback(abstract_surface: *Surface, func: SurfaceObserverCallback, data: ?*anyopaque) Status;
    pub const observerAddFillCallback = cairo_surface_observer_add_fill_callback;

    extern fn cairo_surface_observer_add_stroke_callback(abstract_surface: *Surface, func: SurfaceObserverCallback, data: ?*anyopaque) Status;
    pub const observerAddStrokeCallback = cairo_surface_observer_add_stroke_callback;

    extern fn cairo_surface_observer_add_glyphs_callback(abstract_surface: *Surface, func: SurfaceObserverCallback, data: ?*anyopaque) Status;
    pub const observerAddGlyphsCallback = cairo_surface_observer_add_glyphs_callback;

    extern fn cairo_surface_observer_add_flush_callback(abstract_surface: *Surface, func: SurfaceObserverCallback, data: ?*anyopaque) Status;
    pub const observerAddFlushCallback = cairo_surface_observer_add_glyphs_callback;

    extern fn cairo_surface_observer_add_finish_callback(abstract_surface: *Surface, func: SurfaceObserverCallback, data: ?*anyopaque) Status;
    pub const observerAddFinishCallback = cairo_surface_observer_add_glyphs_callback;

    extern fn cairo_surface_observer_print(abstract_surface: *Surface, write_func: WriteFunc, closure: ?*anyopaque) Status;
    pub const observerPrint = cairo_surface_observer_print;

    extern fn cairo_surface_observer_elapsed(abstract_surface: *Surface) f64;
    pub const observerElapsed = cairo_surface_observer_elapsed;

    extern fn cairo_surface_reference(surface: *Surface) *Surface;
    pub const reference = cairo_surface_reference;

    extern fn cairo_surface_finish(surface: *Surface) void;
    pub const finish = cairo_surface_finish;

    extern fn cairo_surface_destroy(surface: *Surface) void;
    pub const destroy = cairo_surface_destroy;

    extern fn cairo_surface_get_device(surface: *Surface) ?*Device;
    pub const getDevice = cairo_surface_get_device;

    extern fn cairo_surface_get_reference_count(surface: *Surface) c_uint;
    pub const getReferenceCount = cairo_surface_get_reference_count;

    extern fn cairo_surface_status(surface: *Surface) Status;
    pub const status = cairo_surface_status;

    extern fn cairo_surface_get_type(surface: *Surface) SurfaceType;
    pub const getType = cairo_surface_get_type;

    extern fn cairo_surface_get_content(surface: *Surface) Content;
    pub const getContent = cairo_surface_get_content;

    extern fn cairo_surface_write_to_png(surface: *Surface, filename: [*:0]const u8) Status;
    pub const writeToPng = cairo_surface_write_to_png;

    extern fn cairo_surface_write_to_png_stream(surface: *Surface, write_func: WriteFunc, closure: ?*anyopaque) Status;
    pub const writeToPngStream = cairo_surface_write_to_png_stream;

    extern fn cairo_surface_get_user_data(surface: *Surface, key: *const UserDataKey) ?*anyopaque;
    pub const getUserData = cairo_surface_get_user_data;

    extern fn cairo_surface_set_user_data(surface: *Surface, key: *const UserDataKey, user_data: ?*anyopaque, destroy: DestroyFunc) Status;
    pub const setUserData = cairo_surface_set_user_data;

    extern fn cairo_surface_get_mime_data(surface: *Surface, mime_type: [*:0]const u8, data: *?[*]const u8, length: *c_ulong) void;
    pub const getMimeData = cairo_surface_get_mime_data;

    extern fn cairo_surface_set_mime_data(surface: *Surface, mime_type: [*:0]const u8, data: ?[*]const u8, length: c_ulong, destroy: DestroyFunc, closure: ?*anyopaque) Status;
    pub const setMimeData = cairo_surface_set_mime_data;

    extern fn cairo_surface_supports_mime_type(surface: *Surface, mime_type: [*:0]const u8) c_int;
    pub const supportsMimeType = cairo_surface_supports_mime_type;

    extern fn cairo_surface_get_font_options(surface: *Surface, options: *FontOptions) void;
    pub const getFontOptions = cairo_surface_get_font_options;

    extern fn cairo_surface_flush(surface: *Surface) void;
    pub const flush = cairo_surface_flush;

    extern fn cairo_surface_mark_dirty(surface: *Surface) void;
    pub const markDirty = cairo_surface_mark_dirty;

    extern fn cairo_surface_mark_dirty_rectangle(surface: *Surface, x: c_int, y: c_int, width: c_int, height: c_int) void;
    pub const markDirtyRectangle = cairo_surface_mark_dirty_rectangle;

    extern fn cairo_surface_set_device_scale(surface: *Surface, x_scale: f64, y_scale: f64) void;
    pub const setDeviceScale = cairo_surface_set_device_scale;

    extern fn cairo_surface_get_device_scale(surface: *Surface, x_scale: *f64, y_scale: *f64) void;
    pub const getDeviceScale = cairo_surface_get_device_scale;

    extern fn cairo_surface_set_device_offset(surface: *Surface, x_offset: f64, y_offset: f64) void;
    pub const setDeviceOffset = cairo_surface_set_device_offset;

    extern fn cairo_surface_get_device_offset(surface: *Surface, x_offset: *f64, y_offset: *f64) void;
    pub const getDeviceOffset = cairo_surface_get_device_offset;

    extern fn cairo_surface_set_fallback_resolution(surface: *Surface, x_pixels_per_inch: f64, y_pixels_per_inch: f64) void;
    pub const setFallbackResolution = cairo_surface_set_fallback_resolution;

    extern fn cairo_surface_get_fallback_resolution(surface: *Surface, x_pixels_per_inch: *f64, y_pixels_per_inch: *f64) void;
    pub const getFallbackResolution = cairo_surface_get_fallback_resolution;

    extern fn cairo_surface_copy_page(surface: *Surface) void;
    pub const copyPage = cairo_surface_copy_page;

    extern fn cairo_surface_show_page(surface: *Surface) void;
    pub const showPage = cairo_surface_show_page;

    extern fn cairo_surface_has_show_text_glyphs(surface: *Surface) c_int;
    pub const hasShowTextGlyphs = cairo_surface_has_show_text_glyphs;

    extern fn cairo_image_surface_create(format: Format, width: c_int, height: c_int) *Surface;
    pub const imageCreate = cairo_image_surface_create;

    extern fn cairo_image_surface_create_for_data(data: [*]u8, format: Format, width: c_int, height: c_int, stride: c_int) *Surface;
    pub const imageCreateForData = cairo_image_surface_create_for_data;

    extern fn cairo_image_surface_get_data(surface: *Surface) ?[*]u8;
    pub const imageGetData = cairo_image_surface_get_data;

    extern fn cairo_image_surface_get_format(surface: *Surface) Format;
    pub const imageGetFormat = cairo_image_surface_get_format;

    extern fn cairo_image_surface_get_width(surface: *Surface) c_int;
    pub const imageGetWidth = cairo_image_surface_get_width;

    extern fn cairo_image_surface_get_height(surface: *Surface) c_int;
    pub const imageGetHeight = cairo_image_surface_get_height;

    extern fn cairo_image_surface_get_stride(surface: *Surface) c_int;
    pub const imageGetStride = cairo_image_surface_get_stride;

    extern fn cairo_image_surface_create_from_png(filename: [*:0]const u8) *Surface;
    pub const imageCreateFromPng = cairo_image_surface_create_from_png;

    extern fn cairo_image_surface_create_from_png_stream(read_func: ReadFunc, closure: ?*anyopaque) *Surface;
    pub const imageCreateFromPngStream = cairo_image_surface_create_from_png_stream;

    extern fn cairo_recording_surface_create(content: Content, extents: ?*const Rectangle) *Surface;
    pub const recordingCreate = cairo_recording_surface_create;

    extern fn cairo_recording_surface_ink_extents(surface: *Surface, x0: *f64, y0: *f64, width: *f64, height: *f64) void;
    pub const recordingInkExtents = cairo_recording_surface_ink_extents;

    extern fn cairo_recording_surface_get_extents(surface: *Surface, extents: *Rectangle) c_int;
    pub const recordingGetExtents = cairo_recording_surface_get_extents;
};

pub const mime_type_jpeg = "image/jpeg";
pub const mime_type_png = "image/png";
pub const mime_type_jp2 = "image/jp2";
pub const mime_type_uri = "text/x-uri";
pub const mime_type_unique_id = "application/x-cairo.uuid";
pub const mime_type_jbig2 = "application/x-cairo.jbig2";
pub const mime_type_jbig2_global = "application/x-cairo.jbig2-global";
pub const mime_type_jbig2_global_id = "application/x-cairo.jbig2-global-id";
pub const mime_type_ccitt_fax = "image/g3fax";
pub const mime_type_ccitt_fax_params = "image/x-cairo.ccitt.params";
pub const mime_type_eps = "application/postscript";
pub const mime_type_eps_params = "application/x-cairo.eps.params";

pub const SurfaceType = enum(c_int) {
    image,
    pdf,
    ps,
    xlib,
    xcb,
    glitz,
    quartz,
    win32,
    beos,
    directfb,
    svg,
    os2,
    win32_printing,
    quartz_image,
    script,
    qt,
    recording,
    vg,
    gl,
    drm,
    tee,
    xml,
    skia,
    subsurface,
    cogl,
};

pub const SurfaceObserverMode = enum(c_int) {
    normal = 0,
    record_operations = 0x1,
};

pub const SurfaceObserverCallback = *const fn (observer: *Surface, target: *Surface, data: ?*anyopaque) callconv(.c) void;

pub const Device = opaque {
    extern fn cairo_device_reference(device: *Device) *Device;
    pub const reference = cairo_device_reference;

    extern fn cairo_device_get_type(device: *Device) DeviceType;
    pub const getType = cairo_device_get_type;

    extern fn cairo_device_status(device: *Device) Status;
    pub const status = cairo_device_status;

    extern fn cairo_device_acquire(device: *Device) Status;
    pub const acquire = cairo_device_acquire;

    extern fn cairo_device_release(device: *Device) void;
    pub const release = cairo_device_release;

    extern fn cairo_device_flush(device: *Device) void;
    pub const flush = cairo_device_flush;

    extern fn cairo_device_finish(device: *Device) void;
    pub const finish = cairo_device_finish;

    extern fn cairo_device_destroy(device: *Device) void;
    pub const destroy = cairo_device_destroy;

    extern fn cairo_device_get_reference_count(device: *Device) c_uint;
    pub const getReferenceCount = cairo_device_get_reference_count;

    extern fn cairo_device_get_user_data(device: *Device, key: *const UserDataKey) ?*anyopaque;
    pub const getUserData = cairo_device_get_user_data;

    extern fn cairo_device_set_user_data(device: *Device, key: *const UserDataKey, user_data: ?*anyopaque, destroy: DestroyFunc) Status;
    pub const setUserData = cairo_device_set_user_data;

    extern fn cairo_device_observer_print(abstract_device: *Device, write_func: WriteFunc, closure: ?*anyopaque) Status;
    pub const observerPrint = cairo_device_observer_print;

    extern fn cairo_device_observer_elapsed(abstract_device: *Device) f64;
    pub const observerElapsed = cairo_device_observer_elapsed;

    extern fn cairo_device_observer_paint_elapsed(abstract_device: *Device) f64;
    pub const observerPaintElapsed = cairo_device_observer_paint_elapsed;

    extern fn cairo_device_observer_mask_elapsed(abstract_device: *Device) f64;
    pub const observerMaskElapsed = cairo_device_observer_mask_elapsed;

    extern fn cairo_device_observer_fill_elapsed(abstract_device: *Device) f64;
    pub const observerFillElapsed = cairo_device_observer_fill_elapsed;

    extern fn cairo_device_observer_stroke_elapsed(abstract_device: *Device) f64;
    pub const observerStrokeElapsed = cairo_device_observer_stroke_elapsed;

    extern fn cairo_device_observer_glyphs_elapsed(abstract_device: *Device) f64;
    pub const observerGlyphsElapsed = cairo_device_observer_glyphs_elapsed;
};

pub const DeviceType = enum(c_int) {
    drm,
    gl,
    script,
    xcb,
    xlib,
    xml,
    cogl,
    win32,

    invalid = -1,
};

pub const Pattern = opaque {
    extern fn cairo_pattern_set_dither(pattern: *Pattern, dither: Dither) void;
    pub const setDither = cairo_pattern_set_dither;

    extern fn cairo_pattern_get_dither(pattern: *Pattern) Dither;
    pub const getDither = cairo_pattern_get_dither;

    extern fn cairo_pattern_create_raster_source(user_data: ?*anyopaque, content: Content, width: c_int, height: c_int) *Pattern;
    pub const rasterSourceCreate = cairo_pattern_create_raster_source;

    extern fn cairo_raster_source_pattern_set_callback_data(pattern: *Pattern, data: ?*anyopaque) void;
    pub const rasterSourceSetCallbackData = cairo_raster_source_pattern_set_callback_data;

    extern fn cairo_raster_source_pattern_get_callback_data(pattern: *Pattern) ?*anyopaque;
    pub const rasterSourceGetCallbackData = cairo_raster_source_pattern_get_callback_data;

    extern fn cairo_raster_source_pattern_set_acquire(pattern: *Pattern, acquire: RasterSourceAcquireFunc, release: RasterSourceReleaseFunc) void;
    pub const rasterSourceSetAcquire = cairo_raster_source_pattern_set_acquire;

    extern fn cairo_raster_source_pattern_get_acquire(pattern: *Pattern, acquire: *RasterSourceAcquireFunc, release: *RasterSourceReleaseFunc) void;
    pub const rasterSourceGetAcquire = cairo_raster_source_pattern_get_acquire;

    extern fn cairo_raster_source_pattern_set_snapshot(pattern: *Pattern, snapshot: RasterSourceSnapshotFunc) void;
    pub const rasterSourceSetSnapshot = cairo_raster_source_pattern_set_snapshot;

    extern fn cairo_raster_source_pattern_get_snapshot(pattern: *Pattern) RasterSourceSnapshotFunc;
    pub const rasterSourceGetSnapshot = cairo_raster_source_pattern_get_snapshot;

    extern fn cairo_raster_source_pattern_set_copy(pattern: *Pattern, copy: RasterSourceCopyFunc) void;
    pub const rasterSourceSetCopy = cairo_raster_source_pattern_set_copy;

    extern fn cairo_raster_source_pattern_get_copy(pattern: *Pattern) RasterSourceCopyFunc;
    pub const rasterSourceGetCopy = cairo_raster_source_pattern_get_copy;

    extern fn cairo_raster_source_pattern_set_finish(pattern: *Pattern, finish: RasterSourceFinishFunc) void;
    pub const rasterSourceSetFinish = cairo_raster_source_pattern_set_finish;

    extern fn cairo_raster_source_pattern_get_finish(pattern: *Pattern) RasterSourceFinishFunc;
    pub const rasterSourceGetFinish = cairo_raster_source_pattern_get_finish;

    extern fn cairo_pattern_create_rgb(red: f64, green: f64, blue: f64) *Pattern;
    pub const solidCreateRgb = cairo_pattern_create_rgb;

    extern fn cairo_pattern_create_rgba(red: f64, green: f64, blue: f64, alpha: f64) *Pattern;
    pub const solidCreateRgba = cairo_pattern_create_rgba;

    extern fn cairo_pattern_get_rgba(pattern: *Pattern, red: ?*f64, green: ?*f64, blue: ?*f64, alpha: ?*f64) Status;
    pub const solidGetRgba = cairo_pattern_get_rgba;

    extern fn cairo_pattern_create_for_surface(surface: *Surface) *Pattern;
    pub const surfaceCreate = cairo_pattern_create_for_surface;

    extern fn cairo_pattern_get_surface(pattern: *Pattern, surface: ?**Surface) Status;
    pub const surfaceGet = cairo_pattern_get_surface;

    extern fn cairo_pattern_create_linear(x0: f64, y0: f64, x1: f64, y1: f64) *Pattern;
    pub const linearCreate = cairo_pattern_create_linear;

    extern fn cairo_pattern_get_linear_points(pattern: *Pattern, x0: ?*f64, y0: ?*f64, x1: ?*f64, y1: ?*f64) Status;
    pub const linearGetPoints = cairo_pattern_get_linear_points;

    extern fn cairo_pattern_create_radial(cx0: f64, cy0: f64, radius0: f64, cx1: f64, cy1: f64, radius1: f64) *Pattern;
    pub const radialCreate = cairo_pattern_create_radial;

    extern fn cairo_pattern_get_radial_circles(pattern: *Pattern, x0: ?*f64, y0: ?*f64, r0: ?*f64, x1: ?*f64, y1: ?*f64, r1: ?*f64) Status;
    pub const radialGetCircles = cairo_pattern_get_radial_circles;

    extern fn cairo_pattern_get_color_stop_count(pattern: *Pattern, count: ?*c_int) Status;
    pub const gradientGetColorStopCount = cairo_pattern_get_color_stop_count;

    extern fn cairo_pattern_add_color_stop_rgb(pattern: *Pattern, offset: f64, red: f64, green: f64, blue: f64) void;
    pub const gradientAddColorStopRgb = cairo_pattern_add_color_stop_rgb;

    extern fn cairo_pattern_add_color_stop_rgba(pattern: *Pattern, offset: f64, red: f64, green: f64, blue: f64, alpha: f64) void;
    pub const gradientAddColorStopRgba = cairo_pattern_add_color_stop_rgba;

    extern fn cairo_pattern_get_color_stop_rgba(pattern: *Pattern, index: c_int, offset: ?*f64, red: ?*f64, green: ?*f64, blue: ?*f64, alpha: ?*f64) Status;
    pub const gradientGetColorStopRgba = cairo_pattern_get_color_stop_rgba;

    extern fn cairo_pattern_create_mesh() *Pattern;
    pub const meshCreate = cairo_pattern_create_mesh;

    extern fn cairo_mesh_pattern_begin_patch(pattern: *Pattern) void;
    pub const meshBeginPatch = cairo_mesh_pattern_begin_patch;

    extern fn cairo_mesh_pattern_end_patch(pattern: *Pattern) void;
    pub const meshEndPatch = cairo_mesh_pattern_end_patch;

    extern fn cairo_mesh_pattern_curve_to(pattern: *Pattern, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64) void;
    pub const meshCurveTo = cairo_mesh_pattern_curve_to;

    extern fn cairo_mesh_pattern_line_to(pattern: *Pattern, x: f64, y: f64) void;
    pub const meshLineTo = cairo_mesh_pattern_line_to;

    extern fn cairo_mesh_pattern_move_to(pattern: *Pattern, x: f64, y: f64) void;
    pub const meshMoveTo = cairo_mesh_pattern_move_to;

    extern fn cairo_mesh_pattern_set_control_point(pattern: *Pattern, point_num: c_uint, x: f64, y: f64) void;
    pub const meshSetControlPoint = cairo_mesh_pattern_set_control_point;

    extern fn cairo_mesh_pattern_set_corner_color_rgb(pattern: *Pattern, corner_num: c_uint, red: f64, green: f64, blue: f64) void;
    pub const meshSetCornerColorRgb = cairo_mesh_pattern_set_corner_color_rgb;

    extern fn cairo_mesh_pattern_set_corner_color_rgba(pattern: *Pattern, corner_num: c_uint, red: f64, green: f64, blue: f64, alpha: f64) void;
    pub const meshSetCornerColorRgba = cairo_mesh_pattern_set_corner_color_rgba;

    extern fn cairo_mesh_pattern_get_patch_count(pattern: *Pattern, count: ?*c_uint) Status;
    pub const meshGetPatchCount = cairo_mesh_pattern_get_patch_count;

    extern fn cairo_mesh_pattern_get_path(pattern: *Pattern, patch_num: c_uint) *Path;
    pub const meshGetPath = cairo_mesh_pattern_get_path;

    extern fn cairo_mesh_pattern_get_corner_color_rgba(pattern: *Pattern, patch_num: c_uint, corner_num: c_uint, red: ?*f64, green: ?*f64, blue: ?*f64, alpha: ?*f64) Status;
    pub const meshGetCornerColorRgba = cairo_mesh_pattern_get_corner_color_rgba;

    extern fn cairo_mesh_pattern_get_control_point(pattern: *Pattern, patch_num: c_uint, point_num: c_int, x: ?*f64, y: ?*f64) Status;
    pub const meshGetControlPoint = cairo_mesh_pattern_get_control_point;

    extern fn cairo_pattern_reference(pattern: *Pattern) *Pattern;
    pub const reference = cairo_pattern_reference;

    extern fn cairo_pattern_destroy(pattern: *Pattern) void;
    pub const destroy = cairo_pattern_destroy;

    extern fn cairo_pattern_get_reference_count(pattern: *Pattern) c_uint;
    pub const getReferenceCount = cairo_pattern_get_reference_count;

    extern fn cairo_pattern_status(pattern: *Pattern) Status;
    pub const status = cairo_pattern_status;

    extern fn cairo_pattern_get_user_data(pattern: *Pattern, key: *const UserDataKey) ?*anyopaque;
    pub const getUserData = cairo_pattern_get_user_data;

    extern fn cairo_pattern_set_user_data(pattern: *Pattern, key: *const UserDataKey, user_data: ?*anyopaque, destroy: DestroyFunc) Status;
    pub const setUserData = cairo_pattern_set_user_data;

    extern fn cairo_pattern_get_type(pattern: *Pattern) PatternType;
    pub const getType = cairo_pattern_get_type;

    extern fn cairo_pattern_set_extend(pattern: *Pattern, extend: Extend) void;
    pub const setExtend = cairo_pattern_set_extend;

    extern fn cairo_pattern_get_extend(pattern: *Pattern) Extend;
    pub const getExtend = cairo_pattern_get_extend;

    extern fn cairo_pattern_set_filter(pattern: *Pattern, filter: Filter) void;
    pub const setFilter = cairo_pattern_set_filter;

    extern fn cairo_pattern_get_filter(pattern: *Pattern) Filter;
    pub const getFilter = cairo_pattern_get_filter;
};

pub const PatternType = enum(c_int) {
    solid,
    surface,
    linear,
    radial,
    mesh,
    raster_source,
};

pub const Extend = enum(c_int) {
    none,
    repeat,
    reflect,
    pad,
};

pub const Filter = enum(c_int) {
    fast,
    good,
    best,
    nearest,
    bilinear,
    gaussian,
};

pub const RasterSourceAcquireFunc = *const fn (pattern: *Pattern, callback_data: ?*anyopaque, target: *Surface, extents: *const RectangleInt) callconv(.c) *Surface;
pub const RasterSourceReleaseFunc = *const fn (pattern: *Pattern, callback_data: ?*anyopaque, surface: *Surface) callconv(.c) void;
pub const RasterSourceSnapshotFunc = *const fn (pattern: *Pattern, callback_data: ?*anyopaque) callconv(.c) Status;
pub const RasterSourceCopyFunc = *const fn (pattern: *Pattern, callback_data: ?*anyopaque, other: *const Pattern) callconv(.c) Status;
pub const RasterSourceFinishFunc = *const fn (pattern: *Pattern, callback_data: ?*anyopaque) callconv(.c) void;

pub const Content = enum(c_int) {
    color = 0x1000,
    alpha = 0x2000,
    color_alpha = 0x3000,
};

pub const Format = enum(c_int) {
    invalid = -1,
    argb32 = 0,
    rgb24 = 1,
    a8 = 2,
    a1 = 3,
    rgb16_565 = 4,
    rgb30 = 5,
    rgb96f = 6,
    rgba128f = 7,

    extern fn cairo_format_stride_for_width(format: Format, width: c_int) c_int;
    pub const strideForWidth = cairo_format_stride_for_width;
};

pub const Dither = enum(c_int) {
    none,
    default,
    fast,
    good,
    best,
};

pub const Operator = enum(c_int) {
    clear,

    source,
    over,
    in,
    out,
    atop,

    dest,
    dest_over,
    dest_in,
    dest_out,
    dest_atop,

    xor,
    add,
    saturate,

    multiply,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,
    hsl_hue,
    hsl_saturation,
    hsl_color,
    hsl_luminosity,
};

pub const Antialias = enum(c_int) {
    default,

    none,
    gray,
    subpixel,

    fast,
    good,
    best,
};

pub const FillRule = enum(c_int) {
    winding,
    even_odd,
};

pub const LineCap = enum(c_int) {
    butt,
    round,
    square,
};

pub const LineJoin = enum(c_int) {
    miter,
    round,
    bevel,
};

pub const tag_dest = "cairo.dest";
pub const tag_link = "Link";
pub const tag_content = "cairo.content";
pub const tag_content_ref = "cairo.content_ref";

pub const ScaledFont = opaque {
    extern fn cairo_scaled_font_create(font_face: *FontFace, matrix: *const Matrix, ctm: *const Matrix, options: *FontOptions) *ScaledFont;
    pub const create = cairo_scaled_font_create;

    extern fn cairo_scaled_font_reference(scaled_font: *ScaledFont) *ScaledFont;
    pub const reference = cairo_scaled_font_reference;

    extern fn cairo_scaled_font_destroy(scaled_font: *ScaledFont) void;
    pub const destroy = cairo_scaled_font_destroy;

    extern fn cairo_scaled_font_get_reference_count(scaled_font: *ScaledFont) c_uint;
    pub const getReferenceCount = cairo_scaled_font_get_reference_count;

    extern fn cairo_scaled_font_status(scaled_font: *ScaledFont) Status;
    pub const status = cairo_scaled_font_status;

    extern fn cairo_scaled_font_get_type(scaled_font: *ScaledFont) FontType;
    pub const getType = cairo_scaled_font_get_type;

    extern fn cairo_scaled_font_get_user_data(scaled_font: *ScaledFont, key: *const UserDataKey) ?*anyopaque;
    pub const getUserData = cairo_scaled_font_get_user_data;

    extern fn cairo_scaled_font_set_user_data(scaled_font: *ScaledFont, key: *const UserDataKey, user_data: ?*anyopaque, destroy: DestroyFunc) Status;
    pub const setUserData = cairo_scaled_font_set_user_data;

    extern fn cairo_scaled_font_extents(scaled_font: *ScaledFont, extents: *FontExtents) void;
    pub const extents = cairo_scaled_font_extents;

    extern fn cairo_scaled_font_text_extents(scaled_font: *ScaledFont, utf8: [*:0]const u8, extents: *TextExtents) void;
    pub const textExtents = cairo_scaled_font_text_extents;

    extern fn cairo_scaled_font_glyph_extents(scaled_font: *ScaledFont, glyphs: [*]const Glyph, num_glyphs: c_int, extents: *TextExtents) void;
    pub const glyphExtents = cairo_scaled_font_glyph_extents;

    extern fn cairo_scaled_font_text_to_glyphs(scaled_font: *ScaledFont, x: f64, y: f64, utf8: [*]const u8, utf8_len: c_int, glyphs: *?[*]Glyph, num_glyphs: c_int, clusters: ?*?[*]TextCluster, num_clusters: c_int, cluster_flags: ?*TextClusterFlags) Status;
    pub const textToGlyphs = cairo_scaled_font_text_to_glyphs;

    extern fn cairo_scaled_font_get_font_face(scaled_font: *ScaledFont) *FontFace;
    pub const getFontFace = cairo_scaled_font_get_font_face;

    extern fn cairo_scaled_font_get_font_matrix(scaled_font: *ScaledFont, font_matrix: *Matrix) void;
    pub const getFontMatrix = cairo_scaled_font_get_font_matrix;

    extern fn cairo_scaled_font_get_ctm(scaled_font: *ScaledFont, ctm: *Matrix) void;
    pub const getCtm = cairo_scaled_font_get_ctm;

    extern fn cairo_scaled_font_get_scale_matrix(scaled_font: *ScaledFont, scale_matrix: *Matrix) void;
    pub const getScaleMatrix = cairo_scaled_font_get_scale_matrix;

    extern fn cairo_scaled_font_get_font_options(scaled_font: *ScaledFont, options: *FontOptions) void;
    pub const getFontOptions = cairo_scaled_font_get_font_options;

    extern fn cairo_user_scaled_font_get_foreground_marker(scaled_font: *ScaledFont) *Pattern;
    pub const userGetForegroundMarker = cairo_user_scaled_font_get_foreground_marker;

    extern fn cairo_user_scaled_font_get_foreground_source(scaled_font: *ScaledFont) *Pattern;
    pub const userGetForegroundSource = cairo_user_scaled_font_get_foreground_source;
};

pub const FontFace = opaque {
    extern fn cairo_font_face_reference(font_face: *FontFace) *FontFace;
    pub const reference = cairo_font_face_reference;

    extern fn cairo_font_face_destroy(font_face: *FontFace) void;
    pub const destroy = cairo_font_face_destroy;

    extern fn cairo_font_face_get_reference_count(font_face: *FontFace) c_uint;
    pub const getReferenceCount = cairo_font_face_get_reference_count;

    extern fn cairo_font_face_status(font_face: *FontFace) Status;
    pub const status = cairo_font_face_status;

    extern fn cairo_font_face_get_type(font_face: *FontFace) FontType;
    pub const getType = cairo_font_face_get_type;

    extern fn cairo_font_face_get_user_data(font_face: *FontFace, key: *const UserDataKey) ?*anyopaque;
    pub const getUserData = cairo_font_face_get_user_data;

    extern fn cairo_font_face_set_user_data(font_face: *FontFace, key: *const UserDataKey, user_data: ?*anyopaque, destroy: DestroyFunc) Status;
    pub const setUserData = cairo_font_face_set_user_data;

    extern fn cairo_toy_font_face_create(family: [*:0]const u8, slant: FontSlant, weight: FontWeight) *FontFace;
    pub const toyCreate = cairo_toy_font_face_create;

    extern fn cairo_toy_font_face_get_family(font_face: *FontFace) [*:0]const u8;
    pub const toyGetFamily = cairo_toy_font_face_get_family;

    extern fn cairo_toy_font_face_get_slant(font_face: *FontFace) FontSlant;
    pub const toyGetSlant = cairo_toy_font_face_get_slant;

    extern fn cairo_toy_font_face_get_weight(font_face: *FontFace) FontWeight;
    pub const toyGetWeight = cairo_toy_font_face_get_weight;

    extern fn cairo_user_font_face_create() *FontFace;
    pub const userCreate = cairo_user_font_face_create;

    extern fn cairo_user_font_face_set_init_func(font_face: *FontFace, init_func: UserScaledFontInitFunc) void;
    pub const userSetInitFunc = cairo_user_font_face_set_init_func;

    extern fn cairo_user_font_face_set_render_glyph_func(font_face: *FontFace, render_glyph_func: UserScaledFontRenderGlyphFunc) void;
    pub const userSetRenderGlyphFunc = cairo_user_font_face_set_render_glyph_func;

    extern fn cairo_user_font_face_set_render_color_glyph_func(font_face: *FontFace, render_glyph_func: UserScaledFontRenderGlyphFunc) void;
    pub const userSetRenderColorGlyphFunc = cairo_user_font_face_set_render_color_glyph_func;

    extern fn cairo_user_font_face_set_text_to_glyphs_func(font_face: *FontFace, text_to_glyphs_func: UserScaledFontTextToGlyphsFunc) void;
    pub const userSetTextToGlyphsFunc = cairo_user_font_face_set_text_to_glyphs_func;

    extern fn cairo_user_font_face_set_unicode_to_glyph_func(font_face: *FontFace, unicode_to_glyph_func: UserScaledFontUnicodeToGlyphFunc) void;
    pub const userSetUnicodeToGlyphFunc = cairo_user_font_face_set_unicode_to_glyph_func;

    extern fn cairo_user_font_face_get_init_func(font_face: *FontFace) UserScaledFontInitFunc;
    pub const userGetInitFunc = cairo_user_font_face_get_init_func;

    extern fn cairo_user_font_face_get_render_glyph_func(font_face: *FontFace) UserScaledFontRenderGlyphFunc;
    pub const userGetRenderGlyphFunc = cairo_user_font_face_get_render_glyph_func;

    extern fn cairo_user_font_face_get_render_color_glyph_func(font_face: *FontFace) UserScaledFontRenderGlyphFunc;
    pub const userGetRenderColorGlyphFunc = cairo_user_font_face_get_render_color_glyph_func;

    extern fn cairo_user_font_face_get_text_to_glyphs_func(font_face: *FontFace) UserScaledFontTextToGlyphsFunc;
    pub const userGetTextToGlyphsFunc = cairo_user_font_face_get_text_to_glyphs_func;

    extern fn cairo_user_font_face_get_unicode_to_glyph_func(font_face: *FontFace) UserScaledFontUnicodeToGlyphFunc;
    pub const userGetUnicodeToGlyphFunc = cairo_user_font_face_get_unicode_to_glyph_func;
};

pub const UserScaledFontInitFunc = *const fn (scaled_font: *ScaledFont, cr: *Context, extents: *FontExtents) callconv(.c) Status;
pub const UserScaledFontRenderGlyphFunc = *const fn (scaled_font: *ScaledFont, glyph: c_ulong, cr: *Context, extents: *FontExtents) callconv(.c) Status;
pub const UserScaledFontTextToGlyphsFunc = *const fn (scaled_font: *ScaledFont, utf8: [*]const u8, utf8_len: c_int, glyphs: *?[*]Glyph, num_glyphs: c_int, clusters: ?*?[*]TextCluster, num_clusters: c_int, cluster_flags: ?*TextClusterFlags) callconv(.c) Status;
pub const UserScaledFontUnicodeToGlyphFunc = *const fn (scaled_font: *ScaledFont, unicode: c_ulong, glyph_index: *c_ulong) callconv(.c) Status;

pub const Glyph = extern struct {
    index: c_ulong,
    x: f64,
    y: f64,

    extern fn cairo_glyph_allocate(num_glyphs: c_int) ?[*]Glyph;
    pub const allocate = cairo_glyph_allocate;

    extern fn cairo_glyph_free(glyphs: ?[*]Glyph) void;
    pub const free = cairo_glyph_free;
};

pub const TextCluster = extern struct {
    num_bytes: c_int,
    num_glyphs: c_int,

    extern fn cairo_text_cluster_allocate(num_clusters: c_int) ?[*]TextCluster;
    pub const allocate = cairo_text_cluster_allocate;

    extern fn cairo_text_cluster_free(clusters: ?[*]TextCluster) void;
    pub const free = cairo_text_cluster_free;
};

pub const TextClusterFlags = packed struct(c_int) {
    backward: bool,
    _: @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(c_int) - 1 } }) = 0,
};

pub const TextExtents = extern struct {
    x_bearing: f64,
    y_bearing: f64,
    width: f64,
    height: f64,
    x_advance: f64,
    y_advance: f64,
};

pub const FontExtents = extern struct {
    ascent: f64,
    descent: f64,
    height: f64,
    max_x_advance: f64,
    max_y_advance: f64,
};

pub const FontSlant = enum(c_int) {
    normal,
    italic,
    oblique,
};

pub const FontWeight = enum(c_int) {
    normal,
    bold,
};

pub const SubpixelOrder = enum(c_int) {
    default,
    rgb,
    bgr,
    vrgb,
    vbgr,
};

pub const HintStyle = enum(c_int) {
    default,
    none,
    slight,
    medium,
    full,
};

pub const HintMetrics = enum(c_int) {
    default,
    off,
    on,
};

pub const ColorMode = enum(c_int) {
    default,
    no_color,
    color,
};

pub const FontOptions = opaque {
    extern fn cairo_font_options_create() *FontOptions;
    pub const create = cairo_font_options_create;

    extern fn cairo_font_options_copy(options: *FontOptions) *FontOptions;
    pub const copy = cairo_font_options_copy;

    extern fn cairo_font_options_destroy(options: *FontOptions) void;
    pub const destroy = cairo_font_options_destroy;

    extern fn cairo_font_options_status(options: *FontOptions) Status;
    pub const status = cairo_font_options_status;

    extern fn cairo_font_options_merge(options: *FontOptions, other: *const FontOptions) void;
    pub const merge = cairo_font_options_merge;

    extern fn cairo_font_options_equal(options: *const FontOptions, other: *const FontOptions) c_int;
    pub const equal = cairo_font_options_equal;

    extern fn cairo_font_options_hash(options: *const FontOptions) c_ulong;
    pub const hash = cairo_font_options_hash;

    extern fn cairo_font_options_set_antialias(options: *FontOptions, antialias: Antialias) void;
    pub const setAntialias = cairo_font_options_set_antialias;

    extern fn cairo_font_options_get_antialias(options: *const FontOptions) Antialias;
    pub const getAntialias = cairo_font_options_get_antialias;

    extern fn cairo_font_options_set_subpixel_order(options: *FontOptions, subpixel_order: SubpixelOrder) void;
    pub const setSubpixelOrder = cairo_font_options_set_subpixel_order;

    extern fn cairo_font_options_get_subpixel_order(options: *const FontOptions) SubpixelOrder;
    pub const getSubpixelOrder = cairo_font_options_get_subpixel_order;

    extern fn cairo_font_options_set_hint_style(options: *FontOptions, hint_style: HintStyle) void;
    pub const setHintStyle = cairo_font_options_set_hint_style;

    extern fn cairo_font_options_get_hint_style(options: *const FontOptions) HintStyle;
    pub const getHintStyle = cairo_font_options_get_hint_style;

    extern fn cairo_font_options_set_hint_metrics(options: *FontOptions, hint_metrics: HintMetrics) void;
    pub const setHintMetrics = cairo_font_options_set_hint_metrics;

    extern fn cairo_font_options_get_hint_metrics(options: *const FontOptions) HintMetrics;
    pub const getHintMetrics = cairo_font_options_get_hint_metrics;

    extern fn cairo_font_options_get_variations(options: *FontOptions) [*:0]const u8;
    pub const getVariations = cairo_font_options_get_variations;

    extern fn cairo_font_options_set_variations(options: *FontOptions, variations: [*:0]const u8) void;
    pub const setVariations = cairo_font_options_set_variations;

    extern fn cairo_font_options_set_color_mode(options: *FontOptions, color_mode: ColorMode) void;
    pub const setColorMode = cairo_font_options_set_color_mode;

    extern fn cairo_font_options_get_color_mode(options: *const FontOptions) ColorMode;
    pub const getColorMode = cairo_font_options_get_color_mode;

    extern fn cairo_font_options_get_color_palette(options: *const FontOptions) c_uint;
    pub const getColorPalette = cairo_font_options_get_color_palette;

    extern fn cairo_font_options_set_color_palette(options: *FontOptions, palette_index: c_uint) void;
    pub const setColorPalette = cairo_font_options_set_color_palette;

    extern fn cairo_font_options_set_custom_palette_color(options: *FontOptions, index: c_uint, red: f64, green: f64, blue: f64, alpha: f64) void;
    pub const setCustomPaletteColor = cairo_font_options_set_custom_palette_color;

    extern fn cairo_font_options_get_custom_palette_color(options: *FontOptions, index: c_uint, red: *f64, green: *f64, blue: *f64, alpha: *f64) Status;
    pub const getCustomPaletteColor = cairo_font_options_get_custom_palette_color;
};

pub const color_palette_default = 0;

pub const FontType = enum(c_int) {
    toy,
    ft,
    win32,
    quartz,
    user,
    dwrite,
    _,
};

pub const Path = extern struct {
    status: Status,
    data: *PathData,
    num_data: c_int,

    extern fn cairo_path_destroy(path: *Path) void;
    pub const destroy = cairo_path_destroy;
};

pub const PathData = extern union {
    header: extern struct {
        type: PathDataType,
        length: c_int,
    },
    point: extern struct {
        x: f64,
        y: f64,
    },
};

pub const PathDataType = enum(c_int) {
    move_to,
    line_to,
    curve_to,
    close_path,
};

pub const Region = opaque {
    extern fn cairo_region_create() *Region;
    pub const create = cairo_region_create;

    extern fn cairo_region_create_rectangle(rectangle: *const RectangleInt) *Region;
    pub const createRectangle = cairo_region_create_rectangle;

    extern fn cairo_region_create_rectangles(rects: [*]const RectangleInt, count: c_int) *Region;
    pub const createRectangles = cairo_region_create_rectangles;

    extern fn cairo_region_copy(original: *const Region) *Region;
    pub const copy = cairo_region_copy;

    extern fn cairo_region_reference(region: *Region) *Region;
    pub const reference = cairo_region_reference;

    extern fn cairo_region_destroy(region: *Region) void;
    pub const destroy = cairo_region_destroy;

    extern fn cairo_region_equal(a: *const Region, b: *const Region) c_int;
    pub const equal = cairo_region_equal;

    extern fn cairo_region_status(region: *const Region) void;
    pub const status = cairo_region_status;

    extern fn cairo_region_get_extents(region: *const Region, extents: *RectangleInt) void;
    pub const getExtents = cairo_region_get_extents;

    extern fn cairo_region_num_rectangles(region: *const Region) c_int;
    pub const numRectangles = cairo_region_num_rectangles;

    extern fn cairo_region_get_rectangle(region: *const Region, nth: c_int, rectangle: *RectangleInt) void;
    pub const getRectangle = cairo_region_get_rectangle;

    extern fn cairo_region_is_empty(region: *const Region) c_int;
    pub const isEmpty = cairo_region_is_empty;

    extern fn cairo_region_contains_rectangle(region: *const Region, rectangle: *const RectangleInt) RegionOverlap;
    pub const containsRectangle = cairo_region_contains_rectangle;

    extern fn cairo_region_contains_point(region: *const Region, x: c_int, y: c_int) c_int;
    pub const containsPoint = cairo_region_contains_point;

    extern fn cairo_region_translate(region: *Region, dx: c_int, dy: c_int) void;
    pub const translate = cairo_region_translate;

    extern fn cairo_region_subtract(dst: *Region, other: *const Region) Status;
    pub const subtract = cairo_region_subtract;

    extern fn cairo_region_subtract_rectangle(dst: *Region, rectangle: *const RectangleInt) Status;
    pub const subtractRectangle = cairo_region_subtract_rectangle;

    extern fn cairo_region_union(dst: *Region, other: *const Region) Status;
    pub const @"union" = cairo_region_union;

    extern fn cairo_region_union_rectangle(dst: *Region, rectangle: *const RectangleInt) Status;
    pub const unionRectangle = cairo_region_union_rectangle;

    extern fn cairo_region_xor(dst: *Region, other: *const Region) Status;
    pub const xor = cairo_region_xor;

    extern fn cairo_region_xor_rectangle(dst: *Region, rectangle: *const RectangleInt) Status;
    pub const xorRectangle = cairo_region_xor_rectangle;
};

pub const RegionOverlap = enum(c_int) {
    in,
    out,
    part,
};

extern fn cairo_debug_reset_static_data() void;
pub const debugResetStaticData = cairo_debug_reset_static_data;
