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

  <xsl:template match="core:alias[@name='Int32']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/44 -->
    <xsl:copy>
      <xsl:copy-of select="@*" />

      <type name="gint32" c:type="gint32" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:record[@name='Face'] | core:record[@name='Library']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/45 -->
    <xsl:copy>
      <xsl:attribute name="pointer">1</xsl:attribute>

      <xsl:copy-of select="@* | node()" />
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
