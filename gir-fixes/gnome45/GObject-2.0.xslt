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

  <xsl:template match="core:union[@name='TypeCValue']">
    <!-- https://github.com/ianprime0509/zig-gobject/issues/37 -->
    <!-- Source: https://github.com/gtk-rs/gir-files/blob/7bdd0d3cd0d219b79475e72db6d2e786c4738cad/GObject-2.0.gir#L10918-L10940 -->
    <xsl:copy>
      <xsl:copy-of select="@* | node()" />

      <doc xml:space="preserve">A union holding one collected value.</doc>
      <field name="v_int" writable="1">
        <doc xml:space="preserve">the field for holding integer values</doc>
        <type name="gint" c:type="gint"/>
      </field>
      <field name="v_long" writable="1">
        <doc xml:space="preserve">the field for holding long integer values</doc>
        <type name="glong" c:type="glong"/>
      </field>
      <field name="v_int64" writable="1">
        <doc xml:space="preserve">the field for holding 64 bit integer values</doc>
        <type name="gint64" c:type="gint64"/>
      </field>
      <field name="v_double" writable="1">
        <doc xml:space="preserve">the field for holding floating point values</doc>
        <type name="gdouble" c:type="gdouble"/>
      </field>
      <field name="v_pointer" writable="1">
        <doc xml:space="preserve">the field for holding pointers</doc>
        <type name="gpointer" c:type="gpointer"/>
      </field>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
