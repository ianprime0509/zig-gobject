<?xml version="1.0"?>
<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:core="http://www.gtk.org/introspection/core/1.0"
    xmlns:c="http://www.gtk.org/introspection/c/1.0"
    xmlns:glib="http://www.gtk.org/introspection/glib/1.0">
  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:method[@c:identifier='gst_bit_writer_get_remaining'] |
                       core:method[@c:identifier='gst_byte_writer_put_buffer'] |
                       core:function[@c:identifier='gst_type_find_data_new'] |
                       core:method[@c:identifier='gst_type_find_data_get_caps'] |
                       core:method[@c:identifier='gst_type_find_data_get_probability'] |
                       core:method[@c:identifier='gst_type_find_data_get_typefind'] |
                       core:method[@c:identifier='gst_type_find_data_free']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/138 -->
  </xsl:template>
</xsl:stylesheet>
