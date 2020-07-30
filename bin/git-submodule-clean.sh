#!/bin/bash
##
## Synchronize the .git/config, .git/modules, and .gitmodules of a Git repo.
## Since .gitmodules is checked in we use it as a reference to build the
## entire submodule structure.
##
##@author Lucas Hahn
##@returns 0 on success
##
##
set -u && SCRIPTNAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR=${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

trap 'exit $?' ERR
OPTIND=1
FORCE="${FORCE:-false}"
export FLAGS="${FLAGS:-""}"
while getopts "hdvf" opt
do
    case "$opt" in
        h)
            cat <<-EOF
    Clean git submodules
    usage: $SCRIPTNAME [ flags ]
    flags: -d debug, -v verbose, -f force, -h help
EOF
            exit 0
          ;;
        d)
            export DEBUGGING=true
          ;;
        v)
            export VERBOSE=true
            export FLAGS+=" -v "
          ;;
        f)
          FORCE=true
          ;;
    esac
done
shift $((OPTIND-1))

if ! [[ -e "$SCRIPT_DIR/include.sh" ]]
then echo "error: this script needs an include.sh to run"; exit 1;
else
  source "$SCRIPT_DIR/include.sh"
  source_lib lib-util.sh
fi

if ! in_os mac
then
  log_warning only tested on MacOS
fi


# check for valid .git directory and look for a .gitdir if in nested submodule
if ! [[ -d ${SOURCE_DIR}/.git ]]
then
  log_warning no .git directory found - perhaps this is a nested submodule?
  if ! [[ -f $SOURCE_DIR/.git ]]; then log_warning no valid .gitdir; exit 1; fi
  if gittext="$(cat $SOURCE_DIR/.git)"
  then
    log_verbose checking gitdir
    gitdir="$(echo $gittext | sed 's/.*\://' | tr -d '[:space:]')"
    if ! [[ -d ${SOURCE_DIR}/${gitdir} ]]
    then log_warning no valid gitdir could be found; exit 1
    else log_verbose found a valid gitdir; export GITDIR=$(cd ${gitdir} $$ pwd)
    fi
  else log_warning no valid gitdir could be found; exit 1
  fi
else
  export GITDIR=$(cd ${SOURCE_DIR}/.git && pwd)
fi

if ! [[ -f ${SOURCE_DIR}/.gitmodules ]]
then log_warning no .gitmodules could be found; exit 1; fi

# add submodules found in .gitmodules but not in .git/config or working dir
GITMODULES=${SOURCE_DIR}/.gitmodules
TRUE_URLS="$(git config --file $GITMODULES --name-only --get-regexp url)"

for f in $TRUE_URLS
do
  url="$(git config --file $GITMODULES --get $f)"
  # file not found in .git/config
  if ! [[ $(git config --file ${GITDIR}/config --get $f) ]]
  then
    # calculate the expected path from gitmodules
    name="$(echo $f | cut -d. -f2)"
    path_obj="$(git config --file $GITMODULES --name-only --get-regexp path | grep $name)"
    rel_path="$(git config --file $GITMODULES --get $path_obj)"
    fullpath=${SOURCE_DIR}/${rel_path}
    basepath="$(echo $fullpath | rev | cut -d/ -f2- | rev)"

    # check to see if path already exists - worst case scenario
    if [[ -d $fullpath ]]
    then
      log_verbose conflicting paths found
      if ! $FORCE
      then
        log_warning dryrun: rm -rf $fullpath
        log_warning dryrun: git add $fullpath
        log_warning dryrun: git commit -m \"deleting deprecated $fullpath\"
      else
        log_warning deleting deprecated $fullpath
        rm -rf $fullpath
        rm -rf $SOURCE_DIR/.git/modules/rel_path
        if git add ${fullpath}/*
        then
          if git commit -m "deleting deprecated submodule $name"
          then
            log_verbose depecrated submodule $name deleted
          else
            if ! git rm -r --cached $fullpath
            then
              log_verbose could not delete submodule $name from index; fi
            if ! git commit -m "deleting deprecated submodule $name"
            then
              log_warning could not delete submodule $name; exit 1; fi
          fi
        else log_warning error: something went wrong deleting $name; fi
      fi
    fi

    # add the new submodule
    log_verbose adding $url

    # check if it is somehow already in the index
    if ! $(cd $basepath && git submodule add $url)
    then
      git rm -r --cached $fullpath
      $(cd $basepath && git submodule add $url)
    fi

    # commit to Git
    git add $fullpath
    git commit -m "adding submodule $name"
  fi
done

# clean out submodules found in .git/config but not in .gitmodules
CFG="$(git config --file ${GITDIR}/config --name-only --get-regexp submodule)"
for f in $CFG
do
  # filter so just check urls
  if [[ $(echo $f | grep url) ]]
  then
    if ! [[ $(git config --file $GITMODULES --name-only --get-regexp $f) ]]
    then
      # submodule not found in .gitmodules so we need to delete
      name=$(echo $f | cut -d. -f2)
      log_verbose "removing $name"
      git config --file ${GITDIR}/config --remove-section submodule.${name}
      rm -rf ${SOURCE_DIR}/${name}
      rm -rf ${SOURCE_DIR}/${GITDIR}/modules/${name}
      if git add "${SOURCE_DIR}/${name}"
      then
        git commit -m "deleting deprecated ${SOURCE_DIR}/${name}"
      elif ! git commit -m "deleting deprecated ${SOURCE_DIR}/${name}"
      then
        if ! git rm -r --cached $fullpath
        then
          log_warning could not delete ${SOURCE_DIR}/${name}
        fi
      fi
    fi
  fi
done

# sync all submodules in the parent repo
GITPATHS="$(git config --file $GITMODULES --name-only --get-regexp path)"
for f in $GITPATHS
do
  path="$(git config --file $GITMODULES --get $f)"
  log_verbose synchronizing $path
  git submodule sync $SOURCE_DIR/$path >/dev/null
done
