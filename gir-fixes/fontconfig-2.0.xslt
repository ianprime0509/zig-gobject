<?xml version="1.0"?>
<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:core="http://www.gtk.org/introspection/core/1.0"
    xmlns:c="http://www.gtk.org/introspection/c/1.0"
    xmlns:glib="http://www.gtk.org/introspection/glib/1.0">
  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/core:repository">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/128 -->
    <xsl:copy>
      <xsl:copy-of select="@* | node()"/>

      <xsl:element name="package" namespace="http://www.gtk.org/introspection/core/1.0">
        <xsl:attribute name="name">fontconfig</xsl:attribute>
      </xsl:element>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
