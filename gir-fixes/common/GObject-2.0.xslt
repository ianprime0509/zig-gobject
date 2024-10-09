<?xml version="1.0"?>
<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns="http://www.gtk.org/introspection/core/1.0"
    xmlns:core="http://www.gtk.org/introspection/core/1.0"
    xmlns:c="http://www.gtk.org/introspection/c/1.0"
    xmlns:glib="http://www.gtk.org/introspection/glib/1.0">
  <xsl:template match="/ | @* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:function[@c:identifier='g_cclosure_new']/core:parameters/core:parameter[@name='destroy_data'] |
                       core:function[@c:identifier='g_cclosure_new_swap']/core:parameters/core:parameter[@name='destroy_data']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/77 -->
    <xsl:copy>
      <xsl:attribute name="nullable">1</xsl:attribute>

      <xsl:copy-of select="@* | node()" />
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
