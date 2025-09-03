<?xml version="1.0"?>
<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns="http://www.gtk.org/introspection/core/1.0"
    xmlns:core="http://www.gtk.org/introspection/core/1.0"
    xmlns:c="http://www.gtk.org/introspection/c/1.0"
    xmlns:glib="http://www.gtk.org/introspection/glib/1.0">
  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:array[../core:doc[contains(text(),'NULL-terminated array')]]">
    <xsl:copy>
      <xsl:attribute name="zero-terminated">1</xsl:attribute>

      <xsl:copy-of select="@* | node()" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:return-value[core:doc[contains(text(),'or %NULL if')]] | core:parameter[core:doc[contains(text(),'%NULL to')]]">
    <xsl:copy>
      <xsl:attribute name="nullable">1</xsl:attribute>

      <xsl:copy-of select="@* | node()" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:method[@c:identifier='g_io_module_load'] |
                       core:method[@c:identifier='g_io_module_unload'] |
                       core:function[@c:identifier='g_io_module_query']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/121 -->
  </xsl:template>
</xsl:stylesheet>
