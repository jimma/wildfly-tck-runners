#! /bin/bash

set -e

TCK_URL=https://download.eclipse.org/jakartaee/faces/4.0/jakarta-faces-tck-4.0.1.zip
TCK_ZIP=jakarta-faces-tck-4.0.1.zip
TCK_HOME="$(pwd .)/faces-tck-4.0.1"
TCK_ROOT=$TCK_HOME/tck
WILDFLY_HOME=wildfly/target/wildfly
NEW_WILDFLY=servers/new-wildfly
OLD_WILDFLY=servers/old-wildfly
VI_HOME=
MVN_ARGS="-B -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn"
UNZIP_ARGS="-o -q"
status=0
newTckStatus=0
oldTckStatus=0

safeRun() {
    set +e
    cmd="$*"
    ${cmd}
    status=$?
    set -e
}

checkExitStatus() {
    exitStatus=0
    if [ ${newTckStatus} -ne 0 ]; then
        echo "The new TCK run failed with ${newTckStatus}."
        exitStatus=1
    fi
    if [ ${oldTckStatus} -ne 0 ]; then
        echo "The old TCK run failed with ${oldTckStatus}."
        exitStatus=1
    fi
    if [ ${exitStatus} -ne 0 ]; then
        echo "At least one of the TCK runs failed. See above for more details."
        exit ${exitStatus}
    fi
}

# Parse incoming parameters
while getopts ":v" opt; do
    case "${opt}" in
        v)
            UNZIP_ARGS="-o"
            MVN_ARGS=""
            ;;
        \?)
            echo "Invalid option: -${OPTARG}" >&2
            printHelp
            exit 1
            ;;
        :)
            echo "Option -${OPTARG} requires an argument" >&2
            exit 1
            ;;
    esac
done

################################################
# Install WildFly if not previously installed. #
################################################

# TODO - Override WildFly Version

if [[ -n $JBOSS_HOME ]] 
then
    if test -d $JBOSS_HOME 
    then
        echo "Using existing server installation " $JBOSS_HOME
        WILDFLY_HOME=$JBOSS_HOME
    else
        echo "JBOSS_HOME points to invalid location " $JBOSS_HOME
        exit 1
    fi
else
    echo "JBOSS_HOME Is NOT Set."
    if ! test -d $WILDFLY_HOME
    then
        echo "Provisioning WildFly."
        pushd wildfly
        mvn ${MVN_ARGS} install -Dprovision.skip=false -Dconfigure.skip=true
        popd
    fi
fi
# At this point WILDFLY_HOME points to the clean server.

####################################
# Create a copy to run the new TCK #
####################################

# First delete any existing clone.
if test -d servers
then
    echo "Deleting existing 'servers' directory."
    rm -fR servers
fi

mkdir servers
echo "Cloning WildFly " $WILDFLY_HOME $NEW_WILDFLY
cp -R $WILDFLY_HOME $NEW_WILDFLY

pushd $NEW_WILDFLY
NEW_WILDFLY=`pwd`
popd

echo "skip provisioning of $NEW_WILDFLY (just use defaults and later delete wildfly/pom.xml + wildfly/configure-server.cli."
#pushd wildfly
#mvn ${MVN_ARGS} install -Dwildfly.home=$NEW_WILDFLY -Dprovision.skip=true -Dconfigure.skip=false
#popd

##############################################################
# Install and configure the TCK if not previously installed. #
##############################################################

if test -f $TCK_ZIP
then
    echo "TCK Already Downloaded."
else
    echo "Downloading TCK."
    curl $TCK_URL -o $TCK_ZIP
fi

if test -d $TCK_HOME
then
    echo "TCK Already Configured."
else
    echo "Configuring TCK."
    unzip ${UNZIP_ARGS} $TCK_ZIP
    cp $TCK_ROOT/pom.xml $TCK_ROOT/original-pom.xml
    echo "skipping xsltproc until we know if we want to translate something in $TCK_ROOT/pom.xml"
    # xsltproc wildfly-mods/transform.xslt $TCK_ROOT/original-pom.xml > $TCK_ROOT/pom.xml
fi

#######################
# Execute the New TCK #
#######################

#echo "Executing NEW Jakarta Faces TCK."
#pushd $TCK_ROOT
#mvn ${MVN_ARGS} clean -pl '!old-tck,!old-tck/build,!old-tck/run'
#mkdir target
#safeRun mvn ${MVN_ARGS} install -Pnew-wildfly -pl '!old-tck,!old-tck/build,!old-tck/run' -Dtest.wildfly.home=$NEW_WILDFLY -fae
#newTckStatus=${status}
#popd

##################
# Old TCK Runner #
##################

export OLD_TCK_HOME=$TCK_ROOT/old-tck/source/release/JSF_BUILD/latest/faces-tck

if [[ -n $TCK_PORTING_KIT ]] 
then
    echo "Hold on tight!"
    
    ANT_URL=https://dlcdn.apache.org//ant/binaries/apache-ant-1.9.16-bin.zip
    ANT_CONTRIB_URL=https://sourceforge.net/projects/ant-contrib/files/ant-contrib/1.0b3/ant-contrib-1.0b3-bin.zip/download
    ANT_ZIP=apache-ant-1.9.16-bin.zip
    ANT_CONTRIB_ZIP=ant-contrib-1.0b3-bin.zip
    export ANT_HOME=$PWD/apache-ant-1.9.16
    export PATH=$ANT_HOME/bin:$PATH
    if ! test -d $ANT_HOME
    then
        echo "Installing Ant."
        if [ ! -f "${ANT_ZIP}" ]; then
            curl $ANT_URL -o $ANT_ZIP
        fi
        unzip ${UNZIP_ARGS} $ANT_ZIP
        if [ ! -f "${ANT_CONTRIB_ZIP}" ]; then
            wget -q --no-check-certificate $ANT_CONTRIB_URL -O $ANT_CONTRIB_ZIP
        fi
        unzip ${UNZIP_ARGS} ${ANT_CONTRIB_ZIP}
        mv ant-contrib/ant-contrib-1.0b3.jar $ANT_HOME/lib
    fi
    ls -l $ANT_HOME/lib
    ENV_ROOT=`pwd`
    export TS_HOME=$OLD_TCK_HOME
    export TS_HOME_ROOT=$PWD
    export JEETCK_MODS=$TCK_PORTING_KIT
    export JAVAEE_HOME=$ENV_ROOT/$OLD_WILDFLY
    export JBOSS_HOME=$JAVAEE_HOME

    GLASSFISH_URL=https://download.eclipse.org/ee4j/glassfish/glassfish-7.0.0-SNAPSHOT-nightly.zip
    GLASSFISH_ZIP=glassfish-7.0.0-SNAPSHOT-nightly.zip
    GLASSFISH_HOME=glassfish7
    export JAVAEE_HOME_RI=$ENV_ROOT/$GLASSFISH_HOME/glassfish
    export DERBY_HOME=$ENV_ROOT/$GLASSFISH_HOME/javadb

    echo "Creating Environment File."
    echo "# Faces TCK Environment." > environment
    echo "export TS_HOME=$TS_HOME" >> environment
    echo "export JEETCK_MODS=$JEETCK_MODS" >> environment
    echo "export JAVAEE_HOME=$JAVAEE_HOME" >> environment
    echo "export JBOSS_HOME=$JBOSS_HOME" >> environment
    echo "export JAVAEE_HOME_RI=$JAVAEE_HOME_RI" >> environment
    echo "export DERBY_HOME=$DERBY_HOME" >> environment

    if ! test -d $GLASSFISH_HOME
    then
        echo "Installing GlassFish"
        curl $GLASSFISH_URL -o $GLASSFISH_ZIP
        unzip ${UNZIP_ARGS} $GLASSFISH_ZIP
    fi

    echo "Cloning WildFly " $WILDFLY_HOME $OLD_WILDFLY
    cp -R $WILDFLY_HOME $OLD_WILDFLY

    if ! test -d $OLD_TCK_HOME
    then
        echo "Preparing Old TCK."
        pushd $TCK_ROOT/old-tck/build
        mvn ${MVN_ARGS} install
        popd
        
        pushd $TCK_ROOT/old-tck/source/release/JSF_BUILD/latest/
        echo "about to unzip $TCK_ROOT/old-tck/source/release/JSF_BUILD/latest/faces-tck.zip from $PWD"
        # wildfly-tck-runners/faces will contain faces-tck folder
        unzip ${UNZIP_ARGS} faces-tck.zip
        popd
        pushd $JEETCK_MODS
        $ANT_HOME/bin/ant clean
        $ANT_HOME/bin/ant -Dprofile=full
        popd
    fi

    echo "Configuring WildFly for the Old TCK"
    pushd $TS_HOME/bin
    # switch from jaspic.home to jsf.home and javaee.home to faces.home
    # update javaee.classes=
    echo "ignore the ant config.vi for now until we make that work or not"
    # $ANT_HOME/bin/ant config.vi
    sed -i 's/javaee.classes=/jsf.classes=/1' -i $TS_HOME/bin/ts.jte

    sed -i 's/jaspic.home/jsf.home/1' -i $TS_HOME/bin/ts.jte
    sed -i 's/javaee.home/faces.home/1' -i $TS_HOME/bin/ts.jte
    sed -i '/webServerHost=/ s/=.*/=localhost/' -i $TS_HOME/bin/ts.jte
    sed -i '/webServerPort=/ s/=.*/=8080/' -i $TS_HOME/bin/ts.jte
    popd
    pushd $TS_HOME/bin
    # Delete the old file if it exists
    if [ -f "${TS_HOME}/ts.jte" ]; then
        rm -v "${TS_HOME}/ts.jte"
    fi
    ln -s $TS_HOME/bin/ts.jte $TS_HOME/ts.jte
    popd

    # Configure the TCK modules
    echo "TS_HOME=${TS_HOME}"
    safeRun "${JBOSS_HOME}/bin/jboss-cli.sh" --command="module remove --name=com.sun.ts"
    MODULE_RESOURCES="${TS_HOME}/lib/tsharness.jar:${TS_HOME}/lib/javatest.jar:${TS_HOME}/lib/jsftck.jar:${JEETCK_MODS}/output/lib/jboss-porting.jar"
    CLI_COMMAND="module add --name=com.sun.ts --resources=${MODULE_RESOURCES} --dependencies=org.wildfly.common,org.wildfly.security.elytron,javaee.api,org.jboss.logging,org.jboss.ejb-client --export-dependencies=javax.rmi.api,org.apache.derby.embedded"
    echo "Adding com.sun.ts module"
    "${JBOSS_HOME}/bin/jboss-cli.sh" --command="${CLI_COMMAND}"

    safeRun "${JBOSS_HOME}/bin/jboss-cli.sh" --command="module remove --name=org.apache.derby.client"
    MODULE_RESOURCES="${DERBY_HOME}/lib/derbyclient.jar:${DERBY_HOME}/lib/derbyshared.jar:${DERBY_HOME}/lib/derbytools.jar"
    CLI_COMMAND="module add --name=org.apache.derby.client --resources=${MODULE_RESOURCES} --dependencies=jakarta.servlet.api,jakarta.transaction.api"
    echo "Adding org.apache.derby.client module"
    "${JBOSS_HOME}/bin/jboss-cli.sh" --command="${CLI_COMMAND}"

    safeRun "${JBOSS_HOME}/bin/jboss-cli.sh" --command="module remove --name=org.apache.derby.embedded"
    MODULE_RESOURCES="${DERBY_HOME}/lib/derby.jar:${DERBY_HOME}/lib/derbyshared.jar:${DERBY_HOME}/lib/derbytools.jar"
    CLI_COMMAND="module add --name=org.apache.derby.embedded --resources=${MODULE_RESOURCES} --dependencies=javax.api,jakarta.servlet.api,jakarta.transaction.api"
    echo "Adding org.apache.derby.embedded module"
    "${JBOSS_HOME}/bin/jboss-cli.sh" --command="${CLI_COMMAND}"

    echo "Starting WildFly"
    pushd $JBOSS_HOME/bin 
    ./standalone.sh  &
    sleep 5

	NUM=0
	while true
	do

	NUM=$[$NUM + 1]
	if (("$NUM" > "20")); then
        echo "Successful application server startup not confirmed! Will run tests anyway."
	    break
	fi

	if ./jboss-cli.sh --connect command=':read-attribute(name=server-state)' | grep running; then
	    echo "Server is running"
	    break
	fi
	    echo "Server is not yet running"
	    sleep 5
	done
    popd

    # Add the global module
    "${JBOSS_HOME}/bin/jboss-cli.sh" -c --command="/subsystem=ee:write-attribute(name=global-modules, value=[{name=com.sun.ts}, {name=org.apache.derby.client}, {name=org.apache.derby.embedded}])"

    echo "Executing OLD TCK."
    pushd $TS_HOME/src/com/sun/ts/tests/jsf
    ant -Dutil.dir="${TCK_HOME}" -Djboss.deploy.dir="${JBOSS_HOME}/standalone/deployments" deploy.all
    echo "Now really Executing OLD TCK."
    safeRun ant -Dutil.dir="${TCK_HOME}" -Djboss.deploy.dir="${JBOSS_HOME}/standalone/deployments" run.all runclient
    oldTckStatus=${status}
    popd

    echo "Stopping WildFly"
    $JBOSS_HOME/bin/jboss-cli.sh -c --command="shutdown"
    echo "Stopping Derby"
    pushd $DERBY_HOME/bin
    ./stopNetworkServer &
    popd
    sleep 5
fi

checkExitStatus
echo "Execution Complete."
sha256sum $TCK_ZIP
