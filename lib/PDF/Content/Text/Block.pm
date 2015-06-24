use v6;

use PDF::Content::Text::Line;
use PDF::Content::Text::Atom;

class PDF::Content::Text::Block {
    has Numeric $.line-height;
    has Numeric $.font-height;
    has $.width;
    has $.height;
    has @.lines;
    has @.overflow is rw;
    has $.font-size;

    method actual-width  { @!lines.max({ .actual-width }); }
    method actual-height { (+@!lines - 1) * $!line-height  +  $!font-height }

    multi submethod BUILD(Str :$text!,
                          :$font!, :$font-size=16, :$!font-height = $font.height( $font-size ),
                          :$word-spacing = $font.stringwidth( ' ', $font-size ),
                          :$kern = False,
                          *%etc) {
        # assume uniform simple text, for now
        my @chunks = $text.comb(/ \w [ [ \w | <:Punctuation > ] <![ \- ]> ]* '-'?
                                || .
                                /).map( -> $word {
                                    $kern
                                        ?? $font.kern($word, $font-size, :$kern).list
                                        !! $font.encode($word)
                                 });

        constant BREAK-WS = rx/ <[ \c[NO-BREAK SPACE] \c[NARROW NO-BREAK SPACE] \c[WORD JOINER] ]> /;
        constant NO-BREAK-WS = rx/ <![ \c[NO-BREAK SPACE] \c[NARROW NO-BREAK SPACE] \c[WORD JOINER] ]> \s /;

        my @atoms;
        while @chunks {
            my $content = @chunks.shift;
            my %atom = :$content;
            %atom<space> = @chunks && @chunks[0] ~~ Numeric
                ?? @chunks.shift
                !! 0;
            %atom<width> = $font.stringwidth($content, $font-size);
            # don't atomize regular white-space
            next if $content ~~ NO-BREAK-WS;
            my $followed-by-ws = @chunks && @chunks[0] ~~ NO-BREAK-WS;
            my $kerning = %atom<space> < 0;

            my $atom = PDF::Content::Text::Atom.new( |%atom );
            if $kerning {
                $atom.sticky = True;
            }
            elsif $atom.content ~~ BREAK-WS {
                $atom.elastic = True;
                $atom.sticky = True;
                @atoms[*-1].sticky = True
                    if @atoms;
            }
            elsif $followed-by-ws {
                $atom.elastic = True;
                $atom.space += $word-spacing;
            }

            @atoms.push: $atom;
        }

        self.BUILD( :@atoms, :$font-size, |%etc );
    }

    multi submethod BUILD(:@atoms! is copy,
                     Numeric :$!line-height!,
                     Numeric :$!font-size,
                     Numeric :$!width?,      #| optional constraint
                     Numeric :$!height?,     #| optional constraint
        ) is default {

        my $line;
        my $line-width = 0.0;

        while @atoms {

            my @word;
            my $atom;

            repeat {
                $atom = @atoms.shift;
                @word.push: $atom;
            } while $atom.sticky && @atoms;

            my $word-width = [+] @word.map({ .width + .space });
            my $trailing-space = @word[*-1].space;

            if !$line || ($!width && $line.atoms && $line-width + $word-width - $trailing-space > $!width) {
                last if $!height && (@!lines + 1)  *  $!line-height > $!height;
                $line = PDF::Content::Text::Line.new();
                $line-width = 0.0;
                @!lines.push: $line;
            }

            $line.atoms.push: @word;
            $line-width += $word-width;
        }

        for @!lines {
            .atoms[*-1].elastic = False;
            .atoms[*-1].space = 0;
        }

        $!width //= self.actual-width;
        $!height //= self.actual-height;

        @!overflow = @atoms;
    }

    method align($mode) {
        .align($mode, :$!width )
            for self.lines;
    }

    method content {

        my @content = $.lines.map({
                ( .content(:$.font-size), 'T*')
            });

        @content.unshift( (:TL[ :real($!line-height) ] ) )
            if +$.lines > 1;

        @content;
    }

}
