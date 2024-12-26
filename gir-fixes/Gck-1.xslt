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

  <xsl:template match="core:type[@c:type='CK_SESSION_HANDLE']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/87 -->
    <!-- See CK_SESSION_HANDLE in http://docs.oasis-open.org/pkcs11/pkcs11-base/v2.40/os/pkcs11-base-v2.40-os.html -->
    <xsl:copy>
      <xsl:attribute name="name">gulong</xsl:attribute>
      <xsl:attribute name="c:type">gulong</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:type[@c:type='CK_FUNCTION_LIST_PTR']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/87 -->
    <!-- See CK_FUNCTION_LIST_PTR in http://docs.oasis-open.org/pkcs11/pkcs11-base/v2.40/os/pkcs11-base-v2.40-os.html -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:type[@c:type='CK_NOTIFY']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/87 -->
    <!-- See CK_NOTIFY in http://docs.oasis-open.org/pkcs11/pkcs11-base/v2.40/os/pkcs11-base-v2.40-os.html -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
