#!/bin/sh
#
# Verify that a last match wins in a Runas_List.
# A negated user or group at the end takes precedence.
#

: ${TESTSUDOERS=testsudoers}

exec 2>&1

$TESTSUDOERS -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (ALL, !root) /bin/ls
EOF

$TESTSUDOERS -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (ALL, !root, operator) /bin/ls
EOF

$TESTSUDOERS -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (ALL, operator, !root) /bin/ls
EOF

$TESTSUDOERS -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (root, !root) /bin/ls
EOF

$TESTSUDOERS -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (root, !root, operator) /bin/ls
EOF

$TESTSUDOERS -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (root, operator, !root) /bin/ls
EOF

$TESTSUDOERS -u admin -g wheel -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (:ALL, !wheel) /bin/ls
EOF

$TESTSUDOERS -u admin -g wheel -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (:ALL, !wheel, operator) /bin/ls
EOF

$TESTSUDOERS -u admin -g wheel -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (:ALL, operator, !wheel) /bin/ls
EOF

$TESTSUDOERS -u admin -g wheel -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (:wheel, !wheel) /bin/ls
EOF

$TESTSUDOERS -u admin -g wheel -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (:wheel, operator, !wheel) /bin/ls
EOF

$TESTSUDOERS -u admin -g wheel -p ${TESTDIR}/passwd -P ${TESTDIR}/group \
    admin /bin/ls <<'EOF'
admin ALL = (:wheel, !wheel, operator) /bin/ls
EOF

exit 0
