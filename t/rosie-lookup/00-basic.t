#!/bin/bash
#-------------------------------------------------------------------------------
# (C) British Crown Copyright 2012-3 Met Office.
#
# This file is part of Rose, a framework for meteorological suites.
#
# Rose is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Rose is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Rose. If not, see <http://www.gnu.org/licenses/>.
#-------------------------------------------------------------------------------
# Basic tests for "rosie lookup".
# Imports of information from a non-empty repository is really done via "rosa
# svn-post-commit", which is tested quite thoroughly in its own test suite.
#-------------------------------------------------------------------------------
. $(dirname $0)/test_header
#-------------------------------------------------------------------------------
if ! python -c 'import cherrypy, sqlalchemy' 2>/dev/null; then
    skip_all 'python: cherrypy or sqlalchemy not installed'
fi
tests 67
#-------------------------------------------------------------------------------
# Setup Rose site/user configuration for the tests.
HOSTNAME=$(hostname)
TZ=UTC
if ! host $HOSTNAME 1>/dev/null 2>&1; then
    HOSTNAME=localhost # Handle computer no domain name
fi
function port_is_busy() {
    local PORT=$1
    if type -P netcat 1>/dev/null; then
        netcat -z $HOSTNAME $PORT
        return $?
    else
        netstat -atun | grep -q "127.0.0.1:$PORT"
        return $?
    fi
}
PORT=$RANDOM
while port_is_busy $PORT; do
    PORT=$RANDOM
done
mkdir repos
svnadmin create repos/foo || exit 1
SVN_URL=file://$PWD/repos/foo

# Setup configuration file.
mkdir conf
cat >conf/rose.conf <<__ROSE_CONF__
[rosie-db]
repos.foo=$PWD/repos/foo
db.foo=sqlite:///$PWD/repos/foo.db

[rosie-id]
local-copy-root=$PWD/roses
prefix-default=foo
prefix-owner-default.foo=fred
prefix-location.foo=$SVN_URL
prefix-ws.foo=http://$HOSTNAME:$PORT/foo

[rosie-ws]
log-dir=$PWD/rosie/log
port=$PORT
__ROSE_CONF__
export ROSE_CONF_PATH=$PWD/conf

# Setup repository - create a suite.
cat >repos/foo/hooks/post-commit <<__POST_COMMIT__
#!/bin/bash
export ROSE_CONF_PATH=$ROSE_CONF_PATH
$ROSE_HOME/sbin/rosa svn-post-commit --debug "\$@" \\
    1>$PWD/rosa-svn-post-commit.out 2>$PWD/rosa-svn-post-commit.err
echo \$? >$PWD/rosa-svn-post-commit.rc
__POST_COMMIT__
chmod +x repos/foo/hooks/post-commit
export LANG=C
cat >rose-suite.info <<'__ROSE_SUITE_INFO'
access-list=*
description=Bad corn ear and pew pull
owner=iris
project=eye pad
title=Should have gone to ...
__ROSE_SUITE_INFO
rosie create -q -y --info-file=rose-suite.info --no-checkout || exit 1
echo "2009-02-13T23:31:30.000000Z" >foo-date-1.txt
svnadmin setrevprop $PWD/repos/foo -r 1 svn:date foo-date-1.txt

# Setup repository - create and update another suite.
# Create a suite.
cat >rose-suite.info <<'__ROSE_SUITE_INFO'
access-list=*
description=Violets are Blue...
owner=roses
project=poetry
title=Roses are Red,...
__ROSE_SUITE_INFO
rosie create -q -y --info-file=rose-suite.info || exit 1
echo "2009-02-13T23:31:31.000000Z" >foo-date-2.txt
svnadmin setrevprop $PWD/repos/foo -r 2 svn:date foo-date-2.txt
# Update this suite.
cat >rose-suite.info <<'__ROSE_SUITE_INFO'
access-list=roses violets
owner=roses
project=poetry
title=Roses are Red, Violets are Blue,...
__ROSE_SUITE_INFO
cp rose-suite.info $PWD/roses/foo-aa001/
(cd $PWD/roses/foo-aa001 && svn commit -q -m "update" && \
     svn update -q) || exit 1
echo "2009-02-13T23:31:32.000000Z" >foo-date-3.txt
svnadmin setrevprop $PWD/repos/foo -r 3 svn:date foo-date-3.txt

# Setup repository - delete the first suite.
TEST_KEY="$TEST_KEY_BASE-3"
rosie delete -q -y foo-aa000 || exit 1
echo "2009-02-13T23:31:33.000000Z" >foo-date-4.txt
svnadmin setrevprop $PWD/repos/foo -r 4 svn:date foo-date-4.txt

# Setup repository - create another suite.
cat >rose-suite.info <<'__ROSE_SUITE_INFO'
access-list=allthebugs
description=Nom nom nom roses
owner=aphids
project=eat roses
title=Eat all the roses!
__ROSE_SUITE_INFO
rosie create -q -y --info-file=rose-suite.info || exit 1
echo "2009-02-13T23:31:34.000000Z" >foo-date-5.txt
svnadmin setrevprop $PWD/repos/foo -r 5 svn:date foo-date-5.txt

# Setup db.
run_pass "$TEST_KEY" $ROSE_HOME/sbin/rosa db-create
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
[INFO] sqlite:///$PWD/repos/foo.db: DB created.
[INFO] $PWD/repos/foo: DB loaded, r5 of 5.
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null

#-------------------------------------------------------------------------------
# Run ws.
TEST_KEY=$TEST_KEY_BASE-rosa-ws
$ROSE_HOME/sbin/rosa ws 0</dev/null 1>rosa-ws.out 2>rosa-ws.err &
ROSA_WS_PID=$!
T_INIT=$(date +%s)
while ! port_is_busy $PORT && (($(date +%s) < T_INIT + 60)); do
    sleep 1
done
if port_is_busy $PORT; then
    pass "$TEST_KEY"
else
    fail "$TEST_KEY"
    exit 1
fi

#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-bad-prefix
run_fail "$TEST_KEY" rosie lookup --prefix=bar poetry
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" </dev/null
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" <<'__ERR__'
No settings found for prefix: 'bar'
__ERR__
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-search-no-results
run_pass "$TEST_KEY" rosie lookup dodo
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite owner project title
url: http://$HOSTNAME:$PORT/foo/search?s=dodo
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-search-no-results-prefix
run_pass "$TEST_KEY" rosie lookup --prefix=foo dodo
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite owner project title
url: http://$HOSTNAME:$PORT/foo/search?s=dodo
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-search-results-specific
run_pass "$TEST_KEY" rosie lookup poetry
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner project title                              
=     foo-aa001/trunk@3 roses poetry  Roses are Red, Violets are Blue,...
url: http://$HOSTNAME:$PORT/foo/search?s=poetry
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-search-results-general
run_pass "$TEST_KEY" rosie lookup a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title                              
=     foo-aa001/trunk@3 roses  poetry    Roses are Red, Violets are Blue,...
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!                 
url: http://$HOSTNAME:$PORT/foo/search?s=a
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-search-results-all-revs
run_pass "$TEST_KEY" rosie lookup --all-revs a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title                              
      foo-aa000/trunk@1 iris   eye pad   Should have gone to ...            
>     foo-aa001/trunk@2 roses  poetry    Roses are Red,...                  
=     foo-aa001/trunk@3 roses  poetry    Roses are Red, Violets are Blue,...
      foo-aa000/trunk@4 iris   eye pad   Should have gone to ...            
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!                 
url: http://$HOSTNAME:$PORT/foo/search?all_revs=True&s=a
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-no-results
run_pass "$TEST_KEY" rosie lookup -Q owner eq violets
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite owner project title
url: http://$HOSTNAME:$PORT/foo/query?q=and+owner+eq+violets
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-specific
run_pass "$TEST_KEY" rosie lookup --query project contains poe
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner project title                              
=     foo-aa001/trunk@3 roses poetry  Roses are Red, Violets are Blue,...
url: http://$HOSTNAME:$PORT/foo/query?q=and+project+contains+poe
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-description
run_pass "$TEST_KEY" rosie lookup -Q description contains nom
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title             
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!
url: http://$HOSTNAME:$PORT/foo/query?q=and+description+contains+nom
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-revision
run_pass "$TEST_KEY" rosie lookup -Q revision gt 3
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title             
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!
url: http://$HOSTNAME:$PORT/foo/query?q=and+revision+gt+3
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-all-revs
run_pass "$TEST_KEY" rosie lookup --all-revs --query title contains a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title                              
      foo-aa000/trunk@1 iris   eye pad   Should have gone to ...            
>     foo-aa001/trunk@2 roses  poetry    Roses are Red,...                  
=     foo-aa001/trunk@3 roses  poetry    Roses are Red, Violets are Blue,...
      foo-aa000/trunk@4 iris   eye pad   Should have gone to ...            
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!                 
url: http://$HOSTNAME:$PORT/foo/query?q=and+title+contains+a&all_revs=True
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-all-revs-description
run_pass "$TEST_KEY" rosie lookup --all-revs --query description contains a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner project title                  
      foo-aa000/trunk@1 iris  eye pad Should have gone to ...
>     foo-aa001/trunk@2 roses poetry  Roses are Red,...      
      foo-aa000/trunk@4 iris  eye pad Should have gone to ...
url: http://$HOSTNAME:$PORT/foo/query?q=and+description+contains+a&all_revs=True
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-all-revs-revision
run_pass "$TEST_KEY" rosie lookup --all-revs -Q revision gt 3
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title                  
      foo-aa000/trunk@4 iris   eye pad   Should have gone to ...
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!     
url: http://$HOSTNAME:$PORT/foo/query?q=and+revision+gt+3&all_revs=True
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-all-revs-multiple-and
run_pass "$TEST_KEY" rosie lookup --all-revs --query title contains a and project eq poetry
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner project title                              
>     foo-aa001/trunk@2 roses poetry  Roses are Red,...                  
=     foo-aa001/trunk@3 roses poetry  Roses are Red, Violets are Blue,...
url: http://$HOSTNAME:$PORT/foo/query?q=and+title+contains+a&q=and+project+eq+poetry&all_revs=True
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-all-revs-multiple-or-0
run_pass "$TEST_KEY" rosie lookup --all-revs --query title contains Roses or owner eq roses
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title                              
>     foo-aa001/trunk@2 roses  poetry    Roses are Red,...                  
=     foo-aa001/trunk@3 roses  poetry    Roses are Red, Violets are Blue,...
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!                 
url: http://$HOSTNAME:$PORT/foo/query?q=and+title+contains+Roses&q=or+owner+eq+roses&all_revs=True
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-query-results-all-revs-multiple-or-1
run_pass "$TEST_KEY" rosie lookup --all-revs --query title contains Roses or owner eq iris
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
local suite             owner  project   title                              
      foo-aa000/trunk@1 iris   eye pad   Should have gone to ...            
>     foo-aa001/trunk@2 roses  poetry    Roses are Red,...                  
=     foo-aa001/trunk@3 roses  poetry    Roses are Red, Violets are Blue,...
      foo-aa000/trunk@4 iris   eye pad   Should have gone to ...            
=     foo-aa002/trunk@5 aphids eat roses Eat all the roses!                 
url: http://$HOSTNAME:$PORT/foo/query?q=and+title+contains+Roses&q=or+owner+eq+iris&all_revs=True
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-verbosity-quiet
run_pass "$TEST_KEY" rosie lookup -q a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
suite            
foo-aa001/trunk@3
foo-aa002/trunk@5
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-custom-format-main-props
run_pass "$TEST_KEY" rosie lookup --format="%suite with %status" a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
suite             with status
foo-aa001/trunk@3 with  M    
foo-aa002/trunk@5 with A     
url: http://$HOSTNAME:$PORT/foo/search?s=a
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-custom-format-other-props
run_pass "$TEST_KEY" rosie lookup \
    --format="%suite %local %description %access-list" a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
suite             local description       access-list
foo-aa001/trunk@3 =     %description      [u'roses', u'violets']
foo-aa002/trunk@5 =     Nom nom nom roses [u'allthebugs']
url: http://$HOSTNAME:$PORT/foo/search?s=a
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-custom-format-other-props-all-revs
run_pass "$TEST_KEY" rosie lookup --all-revs \
    --format="%suite %local %description %access-list" a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
suite             local description               access-list
foo-aa000/trunk@1       Bad corn ear and pew pull [u'*']
foo-aa001/trunk@2 >     Violets are Blue...       [u'*']
foo-aa001/trunk@3 =     %description              [u'roses', u'violets']
foo-aa000/trunk@4       Bad corn ear and pew pull [u'*']
foo-aa002/trunk@5 =     Nom nom nom roses         [u'allthebugs']
url: http://$HOSTNAME:$PORT/foo/search?all_revs=True&s=a
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
TEST_KEY=$TEST_KEY_BASE-custom-format-with-date
run_pass "$TEST_KEY" rosie lookup --format="%suite by %owner at %date" a
file_cmp "$TEST_KEY.out" "$TEST_KEY.out" <<__OUT__
suite             by owner  at date
foo-aa001/trunk@3 by roses  at 2009-02-13 23:31:32 +0000
foo-aa002/trunk@5 by aphids at 2009-02-13 23:31:34 +0000
url: http://$HOSTNAME:$PORT/foo/search?s=a
__OUT__
file_cmp "$TEST_KEY.err" "$TEST_KEY.err" </dev/null
#-------------------------------------------------------------------------------
kill $ROSA_WS_PID