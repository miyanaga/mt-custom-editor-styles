mt-custom-editor-styles
=======================

Makes customizable editor selectable styles easily.
mt-custom-editor-styles
=======================

This Movable Type plugin some feature to customize easily selectable styles in editor - TinyMCE.

# Theme styles

Register to registry like this to add theme specified styles for `rainer`.

    custom_theme_styles:
      rainer:
        show_default_formats: 0
        styles:
          -
            title: Headline2 with my class
            block: h2
            classes: my-class
          -
            title: Headline3 with my class
            block: h3
            classes: my-class


# JSON on config screen

## Additional styles

This plugin adds JSON field to define additional styles in entry configuration screen of blog and website.

See [style_formats](http://www.tinymce.com/wiki.php/Configuration:style_formats) of TinyMCE about the JSON format.

## Switches

You can show or to hide theme specified styles and default formats like headline1~headline6.
