# Copyright 2014 Catalyst
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

package Koha::Email;

use Modern::Perl;
use Email::Valid;
use Email::MessageID;

use base qw(Class::Accessor);
use C4::Context;

__PACKAGE__->mk_accessors(qw( ));

=head1 NAME

Koha::Email

=head1 SYNOPSIS

  use Koha::Email;
  my $email = Koha::Email->new();
  my %mail = $email->create_message_headers({ to => $to_address, from => $from_address,
                                             replyto => $replyto });

=head1 FUNCTIONS

=cut

sub create_message_headers {
    my $self   = shift;
    my $params = shift;
    $params->{from} ||= C4::Context->preference('KohaAdminEmailAddress');
    $params->{charset} ||= 'utf8';
    my %mail = (
        To      => $params->{to},
        From    => $params->{from},
        charset => $params->{charset}
    );

    if (C4::Context->preference('SendAllEmailsTo') && Email::Valid->address(C4::Context->preference('SendAllEmailsTo'))) {
        $mail{'To'} = C4::Context->preference('SendAllEmailsTo');
    }
    else {
        $mail{'Cc'}  = $params->{cc}  if exists $params->{cc};
        $mail{'Bcc'} = $params->{bcc} if exists $params->{bcc};
    }

    if ( C4::Context->preference('ReplytoDefault') ) {
        $params->{replyto} ||= C4::Context->preference('ReplytoDefault');
    }
    if ( C4::Context->preference('ReturnpathDefault') ) {
        $params->{sender} ||= C4::Context->preference('ReturnpathDefault');
    }
    $mail{'Reply-to'}     = $params->{replyto}     if $params->{replyto};
    $mail{'Sender'}       = $params->{sender}      if $params->{sender};
    $mail{'Message'}      = $params->{message}     if $params->{message};
    $mail{'Subject'}      = $params->{subject}     if $params->{subject};
    $mail{'Content-Type'} = $params->{contenttype} if $params->{contenttype};
    $mail{'X-Mailer'}     = "Koha";
    $mail{'Message-ID'}   = Email::MessageID->new->in_brackets;
    return %mail;
}
1;
