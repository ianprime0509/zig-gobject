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

  <xsl:template match="core:method[@c:identifier='gtk_recent_info_get_added']
                       | core:method[@c:identifier='gtk_recent_info_get_application_info']
                       | core:method[@c:identifier='gtk_recent_info_get_modified']
                       | core:method[@c:identifier='gtk_recent_info_get_visited']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/58 -->
  </xsl:template>
</xsl:stylesheet>
