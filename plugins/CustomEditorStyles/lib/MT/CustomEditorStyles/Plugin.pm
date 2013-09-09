package MT::CustomEditorStyles::Plugin;

use strict;
use warnings;

use MT::Util;
use MT::ErrorHandler;

my @common_settings = qw/json show_default_formats show_theme_styles/;

sub plugin {
    MT->component('CustomEditorStyles');
}

sub setting_gui_enabled {
    # See config at first
    my $gui = MT->instance->config('CustomEditorStylesSettingGUI');
    return 0 if defined $gui && !$gui;

    # See registry secondly
    my $reg = MT->registry('custom_editor_styles_plugin');
    return 0 if ref $reg eq 'HASH'
        and defined($reg->{setting_gui})
        and !$reg->{setting_gui};

    1;
}

sub hdlr_HasCustomEditorStyles {
    my ( $ctx, $args ) = @_;
    my $app = MT->instance;

    my $blog = $app->blog or return 0;

    # Theme styles
    my $theme_styles = theme_styles($blog);

    # Blog styles
    my %config;
    my $scope = 'blog:' . $blog->id;
    plugin->load_config(\%config, $scope);
    my $eh = MT::ErrorHandler->new;
    my $blog_styles = validate_styles_json($eh, $config{json});
    my $show_theme_styles = $config{show_theme_styles};

    # Stash them
    $ctx->stash('_custom_editor_show_theme_styles', $show_theme_styles);
    $ctx->stash('_custom_editor_theme_styles', $theme_styles);
    $ctx->stash('_custom_editor_blog_styles', $blog_styles);

    # Return true if theme or blog styles defined
    return 1 if defined $theme_styles
        and ref $theme_styles eq 'ARRAY'
        and scalar @$theme_styles > 0; 

    return 1 if defined $blog_styles
        and ref $blog_styles eq 'ARRAY'
        and scalar @$blog_styles > 0; 

    0;
}

sub hdlr_IfCustomEditorStylesWithDefaults {
    my ( $ctx, $args ) = @_;
    my $app = MT->instance;

    my $blog = $app->blog or return 0;

    styles_with_default_formats($blog);
}

sub hdlr_CustomEditorStyles {
    my ( $ctx, $args ) = @_;
    my $app = MT->instance;

    # Theme and blog styles
    my $show_theme_styles = $ctx->stash('_custom_editor_show_theme_styles');
    my $theme_styles = $ctx->stash('_custom_editor_theme_styles') || [];
    my $blog_styles = $ctx->stash('_custom_editor_blog_styles') || [];

    # Join them and return as JSON
    my @styles;
    push @styles, @$theme_styles if $show_theme_styles;
    push @styles, @$blog_styles;

    MT::Util::to_json(\@styles);
}

sub custom_editor_styles_json {
    my ( $blog ) = @_;

    my %config;
    my $scope = 'blog:' . $blog->id;
    plugin->load_config(\%config, $scope);

    $config{json};
}

sub show_default_formats {
    my ( $blog ) = @_;

    my %config;
    my $scope = 'blog:' . $blog->id;
    plugin->load_config(\%config, $scope);

    $config{show_default_formats};
}

sub theme_styles {
    my ( $blog ) = @_;
    my $theme = $blog->theme;

    my $values = MT->registry('custom_theme_styles', $theme->id)
        || ( $theme->{elements} && $theme->{elements}->{custom_editor_styles} )
        || return;

    return unless ref $values eq 'HASH';

    my $styles = $values->{styles} or return;
    return if ref $styles ne 'ARRAY';

    # Filter and translation
    my @hashes = map {
        my %hash = %$_;
        if ( ref $values->{plugin} ) {
            $hash{title} = $values->{plugin}->translate($_->{title});
        }
        \%hash;
    } grep {
        ref $_ eq 'HASH'
    } @$styles;

    \@hashes;
}

sub styles_with_default_formats {
    my ( $blog ) = @_;

    my $scope = 'blog:' . $blog->id;
    my %config;
    plugin->load_config(\%config, $scope);

    # Return if defined config
    return $config{show_default_formats} 
        if defined $config{show_default_formats};

    # The theme styles say which?
    my $theme = $blog->theme;
    return 1 unless $theme;

    my $values = MT->registry('custom_theme_styles', $theme->id);
    return $values->{show_default_formats}
        if defined $values->{show_default_formats};

    1;
}

sub validate_styles_json {
    my ( $cb, $json ) = @_;

    # Return empty if blank
    return [] if $json =~ /^\s+$/s;

    # Parse as JSON
    local $@;
    my $value;
    eval {
        $value = MT::Util::from_json($json);
    };

    my $err = $@ || plugin->translate('Unknown error');
    return $cb->error( plugin->translate('Bad format as JSON because [_1]', $err) )
        unless defined($value);

    # Styles json must be an array of hash
    return $cb->error( plugin->translate('JSON data must be an array of hash.') )
        unless ref $value eq 'ARRAY';

    foreach my $hash ( @$value ) {
        return $cb->error( plugin->translate('JSON data must be an array of hash.') )
            unless ref $hash eq 'HASH';

        # Each hash requires title
        foreach my $k ( qw/title/ ) {
            my $v = $hash->{$k};
            return $cb->error( plugin->translate('Each hash must have key named [_1].', $k) )
                if !defined($v) or length($v) < 1;
        }
    }

    $value;
}

sub template_param_cfg_entry {
    my ( $cb, $app, $param, $tmpl ) = @_;

    return 1 unless setting_gui_enabled;

    my $blog = $app->blog
        or return $cb->error($app->translate('Invalid parameter'));

    # Insert mt:include to load cfg_styles.tmpl
    my $insert = $tmpl->createElement('include', {
        name => 'cfg_styles.tmpl',
        component => 'CustomEditorStyles',
    });

    my $target = $tmpl->getElementById('content_css');
    $tmpl->insertAfter($insert, $target);

    # Load params from blog plugin settings
    my %config;
    my $scope = 'blog:' . $blog->id;
    plugin->load_config(\%config, $scope);

    $param->{"custom_editor_styles_$_"} = $config{$_}
        foreach @common_settings;

    # Show default formats, is dynamic
    $param->{custom_editor_styles_show_default_formats}
        = styles_with_default_formats($blog)
        unless defined $param->{custom_editor_styles_show_default_formats};

    1;
}

sub cms_save_filter_blog {
    my ( $cb, $app ) = @_;
    my $q = $app->param;

    return 1 unless setting_gui_enabled;

    # Skip if not cfg_entry
    return 1 if $q->param('cfg_screen') ne 'cfg_entry';

    my $blog = $app->blog
        or return $cb->error($app->translate('Invalid parameter'));
    my $json = $q->param('custom_editor_styles_json') || '';

    defined ( my $res = validate_styles_json($app, $json) )
        or return;

    1;
}

sub post_save_blog {
    my ( $cb, $app, $obj ) = @_;
    my $q = $app->param;

    return 1 unless setting_gui_enabled;

    # Skip if not cfg_entry
    return 1 if $q->param('cfg_screen') ne 'cfg_entry';

    my $blog = $app->blog
        or return $cb->error($app->translate('Invalid parameter'));

    # Save settings to blog plugin config
    my %config;
    my $scope = 'blog:' . $blog->id;
    plugin->load_config(\%config, $scope);

    $config{$_} = $q->param("custom_editor_styles_$_")
        foreach @common_settings;

    plugin->save_config(\%config, $scope);

    1;    
}

1;