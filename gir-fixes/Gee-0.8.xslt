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

  <xsl:template match="core:namespace">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/90 -->
    <!-- A definition of the HazardPointerNode type is missing.
      Filling one in as an opaque type is safe regardless of how it's defined,
      and it is only referenced via pointers. -->
    <xsl:copy>
      <xsl:apply-templates select="@* | node()" />

      <core:record name="HazardPointerNode" c:type="GeeHazardPointerNode" opaque="1" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:type[@c:type='GeeFutureMapFunc']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/90 -->
    <!-- This type appears to be a duplicate of another MapFunc, but this one
      is nested inside the Gee.Future type. This may be an artifact of how
      Vala handles such types. -->
    <xsl:copy>
      <xsl:attribute name="name">Gee.Future.MapFunc</xsl:attribute>
      <xsl:attribute name="c:type">GeeFutureMapFunc</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:type[@c:type='GeeFutureLightMapFunc']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/90 -->
    <!-- See the note on GeeFutureMapFunc. -->
    <xsl:copy>
      <xsl:attribute name="name">Gee.Future.LightMapFunc</xsl:attribute>
      <xsl:attribute name="c:type">GeeFutureLightMapFunc</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:type[@c:type='GeeFutureFlatMapFunc']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/90 -->
    <!-- See the note on GeeFutureMapFunc. -->
    <xsl:copy>
      <xsl:attribute name="name">Gee.Future.FlatMapFunc</xsl:attribute>
      <xsl:attribute name="c:type">GeeFutureFlatMapFunc</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:type[@c:type='GeeFutureZipFunc']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/90 -->
    <!-- See the note on GeeFutureMapFunc. -->
    <xsl:copy>
      <xsl:attribute name="name">Gee.Future.ZipFunc</xsl:attribute>
      <xsl:attribute name="c:type">GeeFutureZipFunc</xsl:attribute>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
