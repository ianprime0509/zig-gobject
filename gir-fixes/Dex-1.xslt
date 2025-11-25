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

  <xsl:template match="core:method[@c:identifier='dex_unix_signal_get_signum'][not(core:doc)]">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/142 -->
    <!-- We can distinguish the broken older version from the newer one since
    the older one lacks documentation, but the newer one has it. -->
  </xsl:template>
</xsl:stylesheet>
