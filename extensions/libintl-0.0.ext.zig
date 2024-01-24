const libintl = @import("libintl-0.0");
const mem = @import("std").mem;

pub inline fn gettext(comptime msgid: [:0]const u8) [:0]const u8 {
    return mem.span(libintl.gettext(msgid));
}

pub inline fn dgettext(comptime domainname: [:0]const u8, comptime msgid: [:0]const u8) [:0]const u8 {
    return mem.span(libintl.dgettext(domainname, msgid));
}

pub inline fn dcgettext(comptime domainname: [:0]const u8, comptime msgid: [:0]const u8, comptime category: c_int) [:0]const u8 {
    return mem.span(libintl.dcgettext(domainname, msgid, category));
}

pub inline fn ngettext(comptime msgid1: [:0]const u8, comptime msgid2: [:0]const u8, n: c_ulong) [:0]const u8 {
    return mem.span(libintl.ngettext(msgid1, msgid2, n));
}

pub inline fn dngettext(comptime domainname: [:0]const u8, comptime msgid1: [:0]const u8, comptime msgid2: [:0]const u8, n: c_ulong) [:0]const u8 {
    return mem.span(libintl.dngettext(domainname, msgid1, msgid2, n));
}

pub inline fn dcngettext(comptime domainname: [:0]const u8, comptime msgid1: [:0]const u8, comptime msgid2: [:0]const u8, n: c_ulong, comptime category: c_int) [:0]const u8 {
    return mem.span(libintl.dcngettext(domainname, msgid1, msgid2, n, category));
}

// The pgettext functions are actually just wrappers around the regular
// gettext functions defined in a header:
// https://git.savannah.gnu.org/gitweb/?p=gettext.git;a=blob;f=gnulib-local/lib/gettext.h;h=3d3840f9fcde4080ce3aff097ea73a23ce6e9417;hb=HEAD

const msgctxt_sep = "\x04"; // EOT

pub fn pgettext(comptime msgctxt: [:0]const u8, comptime msgid: [:0]const u8) [:0]const u8 {
    const ctxt_id = msgctxt ++ msgctxt_sep ++ msgid;
    const translation = gettext(ctxt_id);
    return if (translation.ptr == ctxt_id.ptr) msgid else translation;
}

pub inline fn dpgettext(comptime domainname: [:0]const u8, comptime msgctxt: [:0]const u8, comptime msgid: [:0]const u8) [:0]const u8 {
    const ctxt_id = msgctxt ++ msgctxt_sep ++ msgid;
    const translation = dgettext(domainname, ctxt_id);
    return if (translation.ptr == ctxt_id.ptr) msgid else translation;
}

pub inline fn dcpgettext(comptime domainname: [:0]const u8, comptime msgctxt: [:0]const u8, comptime msgid: [:0]const u8, comptime category: c_int) [:0]const u8 {
    const ctxt_id = msgctxt ++ msgctxt_sep ++ msgid;
    const translation = dcgettext(domainname, ctxt_id, category);
    return if (translation.ptr == ctxt_id.ptr) msgid else translation;
}

pub fn npgettext(comptime msgctxt: [:0]const u8, comptime msgid1: [:0]const u8, comptime msgid2: [:0]const u8, n: c_ulong) [:0]const u8 {
    const ctxt_id = msgctxt ++ msgctxt_sep ++ msgid1;
    const translation = ngettext(ctxt_id, msgid2, n);
    if (translation.ptr == ctxt_id.ptr) {
        return if (n == 1) msgid1 else msgid2;
    } else {
        return translation;
    }
}

pub fn dnpgettext(comptime domainname: [:0]const u8, comptime msgctxt: [:0]const u8, comptime msgid1: [:0]const u8, comptime msgid2: [:0]const u8, n: c_ulong) [:0]const u8 {
    const ctxt_id = msgctxt ++ msgctxt_sep ++ msgid1;
    const translation = dngettext(domainname, ctxt_id, msgid2, n);
    if (translation.ptr == ctxt_id.ptr) {
        return if (n == 1) msgid1 else msgid2;
    } else {
        return translation;
    }
}

pub fn dcnpgettext(comptime domainname: [:0]const u8, comptime msgctxt: [:0]const u8, comptime msgid1: [:0]const u8, comptime msgid2: [:0]const u8, n: c_ulong, comptime category: c_int) [:0]const u8 {
    const ctxt_id = msgctxt ++ msgctxt_sep ++ msgid1;
    const translation = dcngettext(domainname, ctxt_id, msgid2, n, category);
    if (translation.ptr == ctxt_id.ptr) {
        return if (n == 1) msgid1 else msgid2;
    } else {
        return translation;
    }
}

pub inline fn textdomain(domainname: [:0]const u8) [:0]const u8 {
    return mem.span(libintl.textdomain(domainname));
}

pub inline fn bindtextdomain(domainname: [:0]const u8, dirname: [:0]const u8) [:0]const u8 {
    return mem.span(libintl.bindtextdomain(domainname, dirname));
}

pub inline fn bindTextdomainCodeset(domainname: [:0]const u8, codeset: [:0]const u8) [:0]const u8 {
    return mem.span(libintl.bindTextdomainCodeset(domainname, codeset));
}
