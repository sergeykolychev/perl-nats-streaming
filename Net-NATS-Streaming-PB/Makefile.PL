use ExtUtils::MakeMaker;
use strict;
use warnings;
my $CC = 'g++';
`protoc --cpp_out=. nats_streaming.proto`;
die "need google protobuf compiler installed" if $!;

WriteMakefile(
    'NAME' => 'Net::NATS::Streaming::PB',
    'VERSION'  => '0.05',
    'OPTIMIZE'      => '-O2 -Wall',
    'CC'            => $CC,
    'LD'            => '$(CC)',
    'CCFLAGS'       => '-fno-strict-aliasing',
    'OBJECT'        => 'nats_streaming.pb.o PB.o',
    'LIBS'          => ["-lprotobuf"],
    'XSOPT'         => '-C++',
    clean           => { FILES => "nats_streaming.pb.cc nats_streaming.pb.h" }
);

