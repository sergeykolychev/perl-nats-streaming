package Net::NATS::Streaming::Client;
use strict;
use warnings;
use Carp 'confess';
use Scalar::Util 'blessed';
use OSSP::uuid;
use Net::NATS::Streaming::PB;
use base 'Net::NATS::Client';
use Class::XSAccessor {
    accessors => [
        'cluster_name',
        'clientID',
        'connect_request',
        'connect_response',
        'cluster_discover_subject'
    ],
};

our $VERSION = '0.01';
our $DEFAULT_CLUSTER_NAME = 'test-cluster';
our $DEFAULT_CLUSTER_DISCOVER_SUBJECT = '_STAN.discover';
our $DEFAULT_ACK_WAIT = 30;
our $DEFAULT_MAX_INFLIGHT = 1024;
our $DEFAULT_CONNECT_TIMEOUT = 2;
our $DEFAULT_MAX_PUB_ACKS_INFLIGHT = 16384;
sub uuidgen {
    OSSP::uuid::uuid_create(my $uuid);
    OSSP::uuid::uuid_make($uuid, OSSP::uuid::UUID_MAKE_V4());
    OSSP::uuid::uuid_export($uuid, OSSP::uuid::UUID_FMT_STR(), my($str), undef);
    OSSP::uuid::uuid_destroy($uuid);
    return $str;
}

sub connect
{
    my $self = shift;
    return unless $self->SUPER::connect(@_);
    my $connect_request = Net::NATS::Streaming::PB::ConnectRequest->new({
        clientID => $self->clientID//uuidgen , heartbeatInbox => $self->new_inbox
    });
    $self->subscribe($connect_request->heartbeatInbox, sub { $self->publish(shift->reply_to, "") });
    my $connect_response;
    $self->cluster_discover_subject($DEFAULT_CLUSTER_DISCOVER_SUBJECT) unless defined $self->cluster_discover_subject;
    $self->cluster_name($DEFAULT_CLUSTER_NAME) unless defined $self->cluster_name;

    $self->request(
        $self->cluster_discover_subject.'.'.$self->cluster_name,
        $connect_request->pack,
        sub {
            $connect_response = Net::NATS::Streaming::PB::ConnectResponse->new(shift->data);
        }
    );
    $self->wait_for_op($DEFAULT_CONNECT_TIMEOUT);
    if(not $connect_response)
    {
        confess("Could not connect to streaming NATS server");
    }
    $self->connect_request($connect_request);
    $self->connect_response($connect_response);
    return 1;
}

sub subscribe_stream
{
    my ($self, $params, $sub) = @_;
    my $subscription_request = Net::NATS::Streaming::PB::SubscriptionRequest->new;
    $subscription_request->copy_from({
        maxInFlight => $DEFAULT_MAX_INFLIGHT,
        ackWaitInSecs => $DEFAULT_ACK_WAIT,
        %{ blessed $params ? $params->to_hashref : $params }
    });
    my $inbox = $self->new_inbox();
    $subscription_request->set_inbox($inbox);
    $subscription_request->set_clientID($self->connect_request->clientID);
    my $subscription_response;
    $self->request(
        $self->connect_response->subRequests,
        $subscription_request->pack,
        sub {
            $subscription_response = Net::NATS::Streaming::PB::SubscriptionResponse->new(shift->data);
        }
    );
    while($self->wait_for_op)
    {
        last if defined $subscription_response;
    }
    return $subscription_response->error if $subscription_response->error;
    my $ackInbox = $subscription_response->ackInbox;
    my $durableName = $subscription_request->durableName;
    my $subject = $subscription_request->subject;
    return $self->subscribe($inbox, sub {
        return Net::NATS::Streaming::PB::UnsubscribeRequest->new({
            inbox => $ackInbox,
            durableName => $durableName,
            subject => $subject,
            clientID => $self->connect_request->clientID
        })->pack unless @_;
        my $msg = Net::NATS::Streaming::PB::MsgProto->new(shift->data);
        my $ack = Net::NATS::Streaming::PB::Ack->new({
            subject  => $msg->subject,
            sequence => $msg->sequence
        });
        $sub->($msg);
        $self->publish($ackInbox, $ack->pack);
    });
}

sub unsubscribe_stream
{
    my ($self, $subscription) = @_;
    $self->publish(
        $self->connect_response->unsubRequests,
        $subscription->callback->()
    );
    $self->unsubscribe($subscription);
}

my %pub_ack_handlers;
my $default_ack_handler = sub {};
sub publish_stream
{
    my ($self, $params, $sub) = @_;
    $params = blessed $params ? $params->to_hashref : $params;
    if($sub and not exists $pub_ack_handlers{ $sub })
    {
        my $inbox = $self->new_inbox();
        $self->subscribe($inbox, sub {
            $sub->(Net::NATS::Streaming::PB::PubAck->new(shift->data));
        });
        $pub_ack_handlers{$sub} = $inbox;
    }
    elsif(not $sub and not exists $pub_ack_handlers{ $default_ack_handler })
    {
        my $inbox = $self->new_inbox();
        $self->subscribe($inbox, $default_ack_handler);
        $pub_ack_handlers{$default_ack_handler} = $inbox;
    }
    my $pub_msg = Net::NATS::Streaming::PB::PubMsg->new({
        (exists $params->{guid} ? () : (guid => uuidgen())),
        reply => $pub_ack_handlers{$sub//$default_ack_handler},
        clientID => $self->connect_request->clientID,
        %{ $params },
    });
    $self->publish(
        $self->connect_response->pubPrefix.'.'.$pub_msg->subject,
        $pub_msg->pack,
        $sub ? $pub_ack_handlers{$sub} : $pub_ack_handlers{$default_ack_handler}
    );
}

sub close_stream
{
    my $self = shift;
    my $close_response;
    $self->request(
        $self->connect_response->closeRequests,
        Net::NATS::Streaming::PB::CloseRequest->new({
            clientID => $self->connect_request->clientID
        })->pack,
        sub { $close_response = Net::NATS::Streaming::PB::CloseResponse->new(shift->data); }
    );
    $self->wait_for_op($DEFAULT_CONNECT_TIMEOUT);
    return $close_response ? $close_response->error : 'failed to close stream';
}

1;

__END__

=head1 NAME

Net::NATS::Streaming::Client - A Perl client for the NATS Streaming messaging system.

=head1 SYNOPSIS

  #
  # Basic Usage
  #
  This class is a subclass of Net::NATS::Client and delegates all networking
  to the parent.

  $client = Net::NATS::Streaming::Client->new(uri => 'nats://localhost:4222', cluster_name => 'test-cluster');
  $client->connect() or die $!;

  # Simple Publisher
  $client->publish_stream({ subject => 'foo', data => 'Hello, World!'});

  # Simple Async Subscriber
  $subscription = $client->subscribe_stream({ subject => 'foo' }, sub {
      my ($message) = @_;
      printf("Received a message: %s\n", $message->data);
  });

  # Unsubscribe
  $client->unsubscribe_stream($subscription);

  # Close stream
  $client->close_stream();

=head1 REPOSITORY

L<https://github.com/sergeykolychev/perl-nats-streaming>

=head1 SEE ALSO

L<https://github.com/carwynmoore/perl-nats>
Net::NATS::Client

=head1 AUTHOR

    Sergey Kolychev, <sergeykolychev.github@gmail.com>

=head1 COPYRIGHT & LICENSE

    Copyright (C) 2017 by Sergey Kolychev <sergeykolychev.github@gmail.com>

    This library is licensed under Apache 2.0 license https://www.apache.org/licenses/LICENSE-2.0

=cut
