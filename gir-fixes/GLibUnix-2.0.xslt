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

  <xsl:template match="core:function[@c:identifier='g_unix_pipe_clear'] |
                       core:function[@c:identifier='g_unix_pipe_close'] |
                       core:function[@c:identifier='g_unix_pipe_get'] |
                       core:function[@c:identifier='g_unix_pipe_open'] |
                       core:function[@c:identifier='g_unix_pipe_steal']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/139 -->
  </xsl:template>
</xsl:stylesheet>
