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

  <xsl:template match="core:method[@c:identifier='ms_error_quark']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_error_get_type']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_release_get_description']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_release_get_version']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_new_from_xml_data']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_bugtracker_uri']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_desktop_launchables']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_developer_name']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_help_uri']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_homepage_uri']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_id']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_name']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_project_license']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_releases']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_ref']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_unref']">
  </xsl:template>
  <xsl:template match="core:method[@c:identifier='ms_component_get_type']">
  </xsl:template>
</xsl:stylesheet>
