#!/usr/bin/env perl

use strict;
use warnings;
use v5.34;
use experimental qw/ signatures /;

# Jekyll wordpress export de-munger

# Before steps :
#
# https://import.jekyllrb.com/docs/wordpressdotcom/
# ruby -r rubygems -e 'require "jekyll-import";
#    JekyllImport::Importers::WordpressDotCom.run({
#      "source" => "wordpress.xml",
#      "no_fetch_images" => false,
#      "assets_folder" => "images"
#    })'

use IO::All -utf8;
use Text::FrontMatter::YAML;
use Mojo::DOM;
use XML::Simple qw/ XMLin /; # "PLEASE DO NOT USE THIS MODULE IN NEW CODE"
use Path::This '$THISDIR';

my $posts = "$THISDIR/../_posts";
my $wpxml = "$THISDIR/wordpress.xml";
my $site_re = qr{^https?://(?:www\.)scienceisdelicious.net}i;

sub posts( $dir = $posts ) {
    io->dir( $dir )->all
}

sub wp_posts( $xml = $wpxml ) {
    my $x = XMLin( $xml );
    [ grep { $_->{'wp:post_type'} eq 'post' } $x->{'channel'}->{'item'}->@* ]
}

sub fm( $file ) {
    Text::FrontMatter::YAML->new(
        document_string => $file->all
    )
}

sub caption_hack( $fm ) {
    $fm->data_text =~ s/\[caption .*?\]<a\ href.*?>(<img.*?>)<\/a>\ ?(.*)?\[\/caption\]/<figure>$1<figcaption>$2<\/figcaption><\/figure>/gr =~
                      s/<!--more-->//gr;
}

sub fixes( $markup, $wp_posts ) {
    my $dom = Mojo::DOM->new( $markup );
    $dom->find('a')->each( sub( $e, $n ) {
        if ( $e->attr('href') =~ /$site_re/ ) {
            my $id = $e->attr('href') =~ s{$site_re/\?p=([0-9]+)}{$1}r;
            my $title = title_for_id( $id, $wp_posts );
            $e->attr(href => "/$title") if $title;
        }
    } );
    $dom->find('p')->each( sub( $e, $n ) {
        $e->replace( $e->content . "\n<!--more-->\n" ) if $n == 2;
    } );
    $dom->content;
}

sub title_for_id( $id, $wp_posts ) {
    my @matches = grep { $_->{'wp:post_id'} eq $id } $wp_posts->@*;
    $matches[0]->{'wp:post_name'}
}

sub go {
    my @posts = posts;
    my $wp_posts = wp_posts;

    for my $post ( @posts ) {
        my $fm = fm( $post );
        my $content = fixes( caption_hack( $fm ), $wp_posts );
        my $data = $fm->frontmatter_hashref;
        my $newfm = Text::FrontMatter::YAML->new(
            data_text => $content,
            frontmatter_hashref => {
                title      => $data->{title},
                date       => $data->{date},
                tags       => $data->{tags},
                categories => $data->{categories},
                layout     => $data->{layout},
                type       => $data->{type},
            }
        );
        $post->print( $newfm->document_string );
    }
}

go;

