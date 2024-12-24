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

  <xsl:template match="core:callback[@c:type='GstDirectControlBindingConvertGValue']/core:parameters/core:parameter[@name='self']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstDirectControlBindingConvertValue']/core:parameters/core:parameter[@name='self']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
