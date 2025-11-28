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

  <xsl:template match="core:callback[@c:type='GHookFinalizeFunc']/core:parameters/core:parameter[@name='hook_list']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:callback[@c:type='GScannerMsgFunc']/core:parameters/core:parameter[@name='scanner']/core:type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/33 -->
    <xsl:copy>
      <xsl:attribute name="name">gpointer</xsl:attribute>
      <xsl:attribute name="c:type">gpointer</xsl:attribute>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:parameter/core:array/core:type">
    <xsl:variable name="paramName" select="../../@name"/>
    <xsl:variable name="doc" select="../../../../core:doc"/>

    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
      <xsl:if test="
        $doc and (
          contains($doc, concat('@', $paramName, ' is %NULL-terminated'))
        )
      ">
        <xsl:attribute name="nullable">1</xsl:attribute>
      </xsl:if>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="core:function[@c:identifier='g_set_prgname_once'] |
                       core:function[@c:identifier='g_set_user_dirs']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/122 -->
  </xsl:template>

  <xsl:template match="core:record[@c:type='GVariant']/@glib:get-type">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/123 -->
  </xsl:template>

  <xsl:template match="core:method[@c:identifier='g_main_context_pusher_new'] |
                       core:function[@c:identifier='g_main_context_pusher_free']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/125 -->
  </xsl:template>

  <xsl:template match="core:function[@c:identifier='g_list_append']/core:parameters/core:parameter[@name='list'] |
                       core:function[@c:identifier='g_list_prepend']/core:parameters/core:parameter[@name='list'] |
                       core:function[@c:identifier='g_list_insert']/core:parameters/core:parameter[@name='list'] |
                       core:function[@c:identifier='g_list_insert_before']/core:parameters/core:parameter[@name='list'] |
                       core:function[@c:identifier='g_slist_append']/core:parameters/core:parameter[@name='list'] |
                       core:function[@c:identifier='g_slist_prepend']/core:parameters/core:parameter[@name='list'] |
                       core:function[@c:identifier='g_slist_insert']/core:parameters/core:parameter[@name='list'] |
                       core:function[@c:identifier='g_slist_insert_before']/core:parameters/core:parameter[@name='slist']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/145 -->
    <xsl:copy>
      <xsl:attribute name="allow-none">1</xsl:attribute>

      <xsl:copy-of select="@* | node()" />
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
