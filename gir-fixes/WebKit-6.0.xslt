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

  <xsl:template match="core:function[@c:identifier='webkit_web_extension_match_pattern_register_custom_URL_scheme']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/157 -->
    <!-- We only conditionally remove the function, for compatibility with the GNOME 48 SDK, which still uses the old name. -->
    <xsl:if test="not(/*//core:function[@c:identifier='webkit_web_extension_match_pattern_register_custom_url_scheme'])">
      <xsl:copy>
        <xsl:apply-templates select="@* | node()" />
      </xsl:copy>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
