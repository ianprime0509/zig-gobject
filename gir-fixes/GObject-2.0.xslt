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

  <xsl:template match="core:callback[@c:type='GClosureNotify']/core:parameters/core:parameter[@name='closure']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
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

  <xsl:template match="core:record[@name='WeakRef']/core:method[@name='get']/core:return-value">
    <xsl:copy>
      <xsl:attribute name="nullable">1</xsl:attribute>
      <xsl:copy-of select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:class[@c:type='GParamSpec']/@glib:get-type |
                       core:class[@c:type='GParamSpecBoolean']/@glib:get-type |
                       core:class[@c:type='GParamSpecBoxed']/@glib:get-type |
                       core:class[@c:type='GParamSpecChar']/@glib:get-type |
                       core:class[@c:type='GParamSpecDouble']/@glib:get-type |
                       core:class[@c:type='GParamSpecEnum']/@glib:get-type |
                       core:class[@c:type='GParamSpecFlags']/@glib:get-type |
                       core:class[@c:type='GParamSpecFloat']/@glib:get-type |
                       core:class[@c:type='GParamSpecGType']/@glib:get-type |
                       core:class[@c:type='GParamSpecInt']/@glib:get-type |
                       core:class[@c:type='GParamSpecInt64']/@glib:get-type |
                       core:class[@c:type='GParamSpecLong']/@glib:get-type |
                       core:class[@c:type='GParamSpecObject']/@glib:get-type |
                       core:class[@c:type='GParamSpecOverride']/@glib:get-type |
                       core:class[@c:type='GParamSpecParam']/@glib:get-type |
                       core:class[@c:type='GParamSpecPointer']/@glib:get-type |
                       core:class[@c:type='GParamSpecString']/@glib:get-type |
                       core:class[@c:type='GParamSpecUChar']/@glib:get-type |
                       core:class[@c:type='GParamSpecUInt']/@glib:get-type |
                       core:class[@c:type='GParamSpecUInt64']/@glib:get-type |
                       core:class[@c:type='GParamSpecULong']/@glib:get-type |
                       core:class[@c:type='GParamSpecUnichar']/@glib:get-type |
                       core:class[@c:type='GParamSpecValueArray']/@glib:get-type |
                       core:class[@c:type='GParamSpecVariant']/@glib:get-type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/124 -->
    <!-- I prefer to enumerate all the affected types explicitly so I can
    evaluate any new instances on a case-by-case basis. -->
  </xsl:template>
</xsl:stylesheet>
