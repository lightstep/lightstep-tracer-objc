#!/bin/bash

# A reprehensible hack of a script that hand-patches thrift-generated cocoa
# code to be less broken.
#
# Goals:
#  - Add .h entries for the methods that clear/reset [optional] thrift struct
#    fields. They are already in the .m files. Why they're not exposed is
#    unclear, but seems like an oversight.
#  - There are places where NSArray* `count`s are passed as parameters where
#    the expected type is `int`. With 64bit cocoa, this loses precision. We
#    manually cast to an int since, in practice, this is fine. (NSArray*s with
#    more than 2^32 elements would cause many other problems first.)
#
# We do this with sed since we can. (So gross!!!)

sed -e 's/\(@property (nonatomic,.*setter=set\)\([^:]*\)\(.*$\)/\1\2\3\
- (void) unset\2;/' Pod/Classes/crouton.h > temp.tmp
cp temp.tmp Pod/Classes/crouton.h
sed -e 's/\(.* size: \)\([[][^ ]* count.*$\)/\1(int)\2/' Pod/Classes/crouton.m > temp.tmp
cp temp.tmp Pod/Classes/crouton.m
rm temp.tmp