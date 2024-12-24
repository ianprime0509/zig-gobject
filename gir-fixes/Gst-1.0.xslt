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

  <xsl:template match="core:callback[@c:type='GstMemoryCopyFunction']/core:parameters/core:parameter[@name='mem']/core:type |
                       core:callback[@c:type='GstMemoryCopyFunction']/core:return-value/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstControlSourceGetValue']/core:parameters/core:parameter[@name='self']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstControlSourceGetValueArray']/core:parameters/core:parameter[@name='self']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstMemoryIsSpanFunction']/core:parameters/core:parameter[@name='mem1']/core:type |
                       core:callback[@c:type='GstMemoryIsSpanFunction']/core:parameters/core:parameter[@name='mem2']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstMemoryMapFullFunction']/core:parameters/core:parameter[@name='mem']/core:type |
                       core:callback[@c:type='GstMemoryMapFullFunction']/core:parameters/core:parameter[@name='info']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstMemoryMapFunction']/core:parameters/core:parameter[@name='mem']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstMemoryShareFunction']/core:parameters/core:parameter[@name='mem']/core:type |
                       core:callback[@c:type='GstMemoryShareFunction']/core:return-value/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstMemoryUnmapFullFunction']/core:parameters/core:parameter[@name='mem']/core:type |
                       core:callback[@c:type='GstMemoryUnmapFullFunction']/core:parameters/core:parameter[@name='info']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GstMemoryUnmapFunction']/core:parameters/core:parameter[@name='mem']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
