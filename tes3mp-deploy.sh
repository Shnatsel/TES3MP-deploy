#!/bin/bash

set -e

VERSION="2.3.0"

HELPTEXT="\
TES3MP-deploy ($VERSION)
Grim Kriegor <grimkriegor@krutt.org>
Licensed under the GNU GPLv3 free license

Usage $0 MODE [OPTIONS]

Modes of operation:
  -i, --install			Prepare and install TES3MP and its dependencies
  -u, --upgrade			Upgrade TES3MP
  -a, --auto-upgrade		Automatically upgrade TES3MP if there are changes on the remote repository
  -r, --rebuild			Simply rebuild TES3MP
  -y, --script-upgrade		Upgrade the TES3MP-deploy script
  -p, --make-package		Make a portable package for easy distribution
  -h, --help			This help text

Options:
  -s, --server-only		Only build the server
  -c, --cores N			Use N cores for building TES3MP and its dependencies
  -v, --commit			HASH Checkout and build a specific TES3MP commit
  -e, --version-string		STRING Set the version string for compatibility

Please report bugs in the GitHub issue page or directly on the TES3MP Discord.
https://github.com/GrimKriegor/TES3MP-deploy
"

#PARSE ARGUMENTS
if [ $# -eq 0 ]; then
  echo -e "$HELPTEXT"
  echo -e "No parameter specified."
  exit 1

else
  while [ $# -ne 0 ]; do
    case $1 in

    #HELP TEXT
    -h | --help )
      echo -e "$HELPTEXT"
      exit 1
    ;;

    #INSTALL DEPENDENCIES AND BUILD TES3MP
    -i | --install )
      INSTALL=true
      REBUILD=true
    ;;

    #CHECK IF THERE ARE UPDATES, PROMPT TO REBUILD IF SO
    -u | --upgrade )
      UPGRADE=true
    ;;

    #UPGRADE AUTOMATICALLY IF THERE ARE CHANGES IN THE UPSTREAM CODE
    -a | --auto-upgrade )
      UPGRADE=true
      AUTO_UPGRADE=true
    ;;

    #REBUILD TES3MP
    -r | --rebuild )
      REBUILD=true
    ;;

    #UPGRADE THE SCRIPT
    -y | --script-upgrade )
      SCRIPT_UPGRADE=true
    ;;

    #MAKE PACKAGE
    -p | --make-package )
      MAKE_PACKAGE=true
    ;;

    #DEFINE INSTALLATION AS SERVER ONLY
    -s | --server-only )
      SERVER_ONLY=true
      touch .serveronly
    ;;

    #BUILD SPECIFIC COMMIT
    -v | --commit )
      if [[ "$2" =~ ^-.* || "$2" == "" ]]; then
        echo -e "\nYou must specify a valid commit hash"
        exit 1
      else
        BUILD_COMMIT=true
        TARGET_COMMIT="$2"
        shift
      fi
    ;;

    #CUSTOM VERSION STRING FOR COMPATIBILITY
    -e | --version-string )
      if [[ "$2" =~ ^-.* || "$2" == "" ]]; then
        echo -e "\nYou must specify a valid version string"
        exit 1
      else
        CHANGE_VERSION_STRING=true
        TARGET_VERSION_STRING="$2"
        shift
      fi
    ;;

    #NUMBER OF CPU THREADS TO USE IN COMPILATION
    -c | --cores )
      if [[ "$2" =~ ^-.* || "$2" == "" ]]; then
        ARG_CORES=""
      else
        ARG_CORES=$2
        shift
      fi
    ;;

    esac
    shift
  done

fi

#EXIT IF NO OPERATION IS SPECIFIED
if [[ ! $INSTALL && ! $UPGRADE && ! $REBUILD && ! $SCRIPT_UPGRADE && ! $MAKE_PACKAGE ]]; then
  echo -e "\nNo operation specified, exiting."
  exit 1
fi

#NUMBER OF CPU CORES USED FOR COMPILATION
if [[ "$ARG_CORES" == "" || "$ARG_CORES" == "0" ]]; then
    CORES="$(cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l)"
else
    CORES="$ARG_CORES"
fi

#DISTRO IDENTIFICATION
DISTRO="$(lsb_release -si | awk '{print tolower($0)}')"

#FOLDER HIERARCHY
BASE="$(pwd)"
CODE="$BASE/code"
DEVELOPMENT="$BASE/build"
KEEPERS="$BASE/keepers"
DEPENDENCIES="$BASE/dependencies"
PACKAGE_TMP="$BASE/package"

#DEPENDENCY LOCATIONS
CALLFF_LOCATION="$DEPENDENCIES"/callff
RAKNET_LOCATION="$DEPENDENCIES"/raknet
TERRA_LOCATION="$DEPENDENCIES"/terra
OSG_LOCATION="$DEPENDENCIES"/osg
BULLET_LOCATION="$DEPENDENCIES"/bullet

#CHECK IF THIS IS A SERVER ONLY INSTALL
if [ -f "$BASE"/.serveronly ]; then
  SERVER_ONLY=true
fi

#INSTALL MODE
if [ $INSTALL ]; then

  #CREATE FOLDER HIERARCHY
  echo -e ">> Creating folder hierarchy"
  mkdir -p "$DEVELOPMENT" "$KEEPERS" "$DEPENDENCIES"

  #CHECK DISTRO AND INSTALL DEPENDENCIES
  echo -e "\n>> Checking which GNU/Linux distro is installed"
  case $DISTRO in
    "arch" | "parabola" | "manjarolinux" )
        echo -e "You seem to be running either Arch Linux, Parabola GNU/Linux-libre or Manjaro"
        sudo pacman -Sy unzip wget git cmake boost openal openscenegraph mygui bullet qt5-base ffmpeg sdl2 unshield libxkbcommon-x11 ncurses #clang35 llvm35

        if [ ! -d "/usr/share/licenses/gcc-libs-multilib/" ]; then
              sudo pacman -S gcc-libs
        fi

        echo -e "\nCreating symlinks for ncurses compatibility"
        LIBTINFO_VER=6
        NCURSES_VER="$(pacman -Q ncurses | awk '{sub(/-[0-9]+/, "", $2); print $2}')"
        sudo ln -s /usr/lib/libncursesw.so."$NETCURSES_VER" /usr/lib/libtinfo.so."$LIBTINFO_VER" 2> /dev/null
        sudo ln -s /usr/lib/libtinfo.so."$LIBTINFO_VER" /usr/lib/libtinfo.so 2> /dev/null
    ;;

    "debian" | "devuan" )
        echo -e "You seem to be running Debian or Devuan"
        sudo apt-get update
        sudo apt-get install unzip wget git cmake libopenal-dev qt5-default libqt5opengl5-dev libopenthreads-dev libopenscenegraph-3.4-dev libsdl2-dev libqt4-dev libboost-filesystem-dev libboost-thread-dev libboost-program-options-dev libboost-system-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libmygui-dev libunshield-dev cmake build-essential libqt4-opengl-dev g++ libncurses5-dev #libbullet-dev
        #echo -e "\nDebian users are required to build OpenSceneGraph from source\nhttps://wiki.openmw.org/index.php?title=Development_Environment_Setup#Build_and_install_OSG\n\nType YES if you want the script to do it automatically (THIS IS BROKEN ATM)\nIf you already have it installed or want to do it manually,\npress ENTER to continue"
        #read INPUT
        #if [ "$INPUT" == "YES" ]; then
        #      echo -e "\nOpenSceneGraph will be built from source"
        #      BUILD_OSG=true
        #      sudo apt-get build-dep openscenegraph libopenscenegraph-dev
        #fi
        sudo apt-get build-dep bullet
        BUILD_BULLET=true
    ;;

    "ubuntu" | "linuxmint" | "elementary" )
        echo -e "You seem to be running Ubuntu, Mint or elementary OS"
        echo -e "\nThe OpenMW PPA repository needs to be enabled\nhttps://wiki.openmw.org/index.php?title=Development_Environment_Setup#Ubuntu\n\nType YES if you want the script to do it automatically\nIf you already have it enabled or want to do it manually,\npress ENTER to continue"
        read INPUT
        if [ "$INPUT" == "YES" ]; then
              echo -e "\nEnabling the OpenMW PPA repository..."
              sudo add-apt-repository ppa:openmw/openmw
              echo -e "Done!"
        fi
        sudo apt-get update
        sudo apt-get install unzip wget git cmake libopenal-dev qt5-default libqt5opengl5-dev libopenthreads-dev libopenscenegraph-3.4-dev libsdl2-dev libqt4-dev libboost-filesystem-dev libboost-thread-dev libboost-program-options-dev libboost-system-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libmygui-dev libunshield-dev cmake build-essential libqt4-opengl-dev g++ libncurses5-dev #llvm-3.5 clang-3.5 libclang-3.5-dev llvm-3.5-dev libbullet-dev
        sudo apt-get build-dep bullet
        BUILD_BULLET=true
    ;;

    "fedora" )
        echo -e "You seem to be running Fedora"
        echo -e "\nFedora users are required to enable the RPMFusion FREE and NON-FREE repositories\nhttps://wiki.openmw.org/index.php?title=Development_Environment_Setup#Fedora_Workstation\n\nType YES if you want the script to do it automatically\nIf you already have it enabled or want to do it manually,\npress ENTER to continue"
        read INPUT
        if [ "$INPUT" == "YES" ]; then
              echo -e "\nEnabling RPMFusion..."
              su -c 'dnf install http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm http://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm'
              echo -e "Done!"
        fi
        sudo dnf --refresh groupinstall development-tools
        sudo dnf --refresh install unzip wget cmake openal-devel OpenSceneGraph-qt-devel SDL2-devel qt4-devel boost-filesystem git boost-thread boost-program-options boost-system ffmpeg-devel ffmpeg-libs bullet-devel gcc-c++ mygui-devel unshield-devel tinyxml-devel cmake #llvm35 llvm clang ncurses
        BUILD_BULLET=true
    ;;

    *)
        echo -e "Could not determine your GNU/Linux distro, press ENTER to continue without installing dependencies"
        read
    ;;
  esac

  #AVOID SOME DEPENDENCIES ON SERVER ONLY MODE
  if [ $SERVER_ONLY ]; then
    BUILD_OSG=""
    BUILD_BULLET=""
  fi

  #PULL SOFTWARE VIA GIT
  echo -e "\n>> Downloading software"
  ! [ -e "$CODE" ] && git clone https://github.com/TES3MP/openmw-tes3mp.git "$CODE"
  ! [ -e "$DEPENDENCIES/"callff ] &&git clone https://github.com/Koncord/CallFF "$DEPENDENCIES/"callff --depth 1
  if [ $BUILD_OSG ] && ! [ -e "$DEPENDENCIES"/osg ] ; then git clone https://github.com/openscenegraph/OpenSceneGraph.git "$DEPENDENCIES"/osg --depth 1; fi
  if [ $BUILD_BULLET ] && ! [ -e "$DEPENDENCIES"/bullet ]; then git clone https://github.com/bulletphysics/bullet3.git "$DEPENDENCIES"/bullet; fi # cannot --depth 1 because we check out specific revision
  ! [ -e "$DEPENDENCIES"/raknet ] && git clone https://github.com/TES3MP/RakNet.git "$DEPENDENCIES"/raknet --depth 1
  ! [ -e "$DEPENDENCIES"/terra ] && if [ $BUILD_TERRA ]; then git clone https://github.com/zdevito/terra.git "$DEPENDENCIES"/terra --depth 1; else wget https://github.com/zdevito/terra/releases/download/release-2016-02-26/terra-Linux-x86_64-2fa8d0a.zip -O "$DEPENDENCIES"/terra.zip; fi
  ! [ -e "$KEEPERS"/PluginExamples ] && git clone https://github.com/TES3MP/PluginExamples.git "$KEEPERS"/PluginExamples

  #COPY STATIC SERVER AND CLIENT CONFIGS
  echo -e "\n>> Copying server and client configs to their permanent place"
  cp "$CODE"/files/tes3mp/tes3mp-{client,server}-default.cfg "$KEEPERS"

  #SET home VARIABLE IN tes3mp-server-default.cfg
  echo -e "\n>> Autoconfiguring"
  sed -i "s|home = .*|home = $KEEPERS/PluginExamples|g" "${KEEPERS}"/tes3mp-server-default.cfg

  #DIRTY HACKS
  echo -e "\n>> Applying some dirty hacks"
  sed -i "s|tes3mp.lua,chat_parser.lua|server.lua|g" "${KEEPERS}"/tes3mp-server-default.cfg #Fixes server scripts
  #sed -i "s|Y #key for switch chat mode enabled/hidden/disabled|Right Alt|g" "${KEEPERS}"/tes3mp-client-default.cfg #Changes the chat key
  #sed -i "s|mp.tes3mp.com|grimkriegor.zalkeen.us|g" "${KEEPERS}"/tes3mp-client-default.cfg #Sets Grim's server as the default

  #BUILD CALLFF
  echo -e "\n>> Building CallFF"
  mkdir -p "$DEPENDENCIES"/callff/build
  cd "$DEPENDENCIES"/callff/build
  cmake ..
  make -j$CORES

  cd "$BASE"

  #BUILD OPENSCENEGRAPH
  if [ $BUILD_OSG ]; then
      echo -e "\n>> Building OpenSceneGraph"
      mkdir -p "$DEPENDENCIES"/osg/build
      cd "$DEPENDENCIES"/osg/build
      git checkout tags/OpenSceneGraph-3.4.0
      rm -f CMakeCache.txt
      cmake ..
      make -j$CORES

      cd "$BASE"
  fi

  #BUILD BULLET
  if [ $BUILD_BULLET ]; then
      echo -e "\n>> Building Bullet Physics"
      mkdir -p "$DEPENDENCIES"/bullet/build
      cd "$DEPENDENCIES"/bullet/build
      git checkout tags/2.86
      rm -f CMakeCache.txt
      cmake -DCMAKE_INSTALL_PREFIX="$DEPENDENCIES"/bullet/install -DBUILD_SHARED_LIBS=1 -DINSTALL_LIBS=1 -DINSTALL_EXTRA_LIBS=1 -DCMAKE_BUILD_TYPE=Release ..
      make -j$CORES

      make install

      cd "$BASE"
  fi

  #BUILD RAKNET
  echo -e "\n>> Building RakNet"
  mkdir -p "$DEPENDENCIES"/raknet/build
  cd "$DEPENDENCIES"/raknet/build
  rm -f CMakeCache.txt
  cmake -DCMAKE_BUILD_TYPE=Release -DRAKNET_ENABLE_DLL=OFF -DRAKNET_ENABLE_SAMPLES=OFF -DRAKNET_ENABLE_STATIC=ON -DRAKNET_GENERATE_INCLUDE_ONLY_DIR=ON ..
  make -j$CORES

  ln -sf "$DEPENDENCIES"/raknet/include/RakNet "$DEPENDENCIES"/raknet/include/raknet #Stop being so case sensitive

  cd "$BASE"

  #BUILD TERRA
  if [ $BUILD_TERRA ]; then
      echo -e "\n>> Building Terra"
      cd "$DEPENDENCIES"/terra/
      make -j$CORES

  else
    if ! [ -e "$DEPENDENCIES"/terra ]; then
      echo -e "\n>> Unpacking and preparing Terra"
      cd "$DEPENDENCIES"
      unzip -o terra.zip
      rm -rf ./terra
      mv --no-target-directory terra-* terra
      rm terra.zip
    fi
  fi

  cd "$BASE"

fi

#CHECK THE REMOTE REPOSITORY FOR CHANGES
if [ $UPGRADE ]; then

  #CHECK IF THERE ARE CHANGES IN THE GIT REMOTE
  echo -e "\n>> Checking the git repository for changes"
  cd "$CODE"
  git remote update
  test "$(git rev-parse @)" != "$(git rev-parse @{u})"
  if [ $? -eq 0 ]; then
    echo -e "\nNEW CHANGES on the git repository"
    GIT_CHANGES=true
  else
    echo -e "\nNo changes on the git repository"
  fi
  cd "$BASE"

  #AUTOMATICALLY UPGRADE IF THERE ARE GIT CHANGES
  if [ $AUTO_UPGRADE ]; then
    if [ $GIT_CHANGES ]; then
      REBUILD="YES"
      UPGRADE="YES"
    else
      echo -e "\nNo new commits, exiting."
      exit 0
    fi
  else
    echo -e "\nDo you wish to rebuild TES3MP? (type YES to continue)"
    read REBUILD_PROMPT
    if [ "$REBUILD_PROMPT" == "YES" ]; then
      REBUILD="YES"
      UPGRADE="YES"
    fi
  fi

fi

#REBUILD TES3MP
if [ $REBUILD ]; then

  #CHECK WHICH DEPENDENCIES ARE PRESENT
  if [ -d "$DEPENDENCIES"/osg ]; then
    BUILD_OSG=true
  fi
  if [ -d "$DEPENDENCIES"/bullet ]; then
    BUILD_BULLET=true
  fi

  #SWITCH TO A SPECIFIC COMMIT
  if [ $BUILD_COMMIT ]; then
    cd "$CODE"
    if [ "$TARGET_COMMIT" == "latest" ]; then
      echo -e "\nChecking out the latest commit."
      git stash
      git pull
      git checkout master
    else
      echo -e "\nChecking out $TARGET_COMMIT"
      git stash
      git pull
      git checkout "$TARGET_COMMIT"
    fi
    cd "$BASE"
  fi

  #CHANGE VERSION STRING
  if [ $CHANGE_VERSION_STRING ]; then
    cd "$CODE"

    if [[ "$TARGET_VERSION_STRING" == "" || "$TARGET_VERSION_STRING" == "latest" ]]; then
      echo -e "\nUsing the upstream version string"
      git stash
      cd "$KEEPERS"/PluginExamples
      git stash
      cd "$CODE"
    else
      echo -e "\nUsing \"$TARGET_VERSION_STRING\" as version string"
      sed -i "s|#define TES3MP_VERSION .*|#define TES3MP_VERSION \"$TARGET_VERSION_STRING\"|g" ./components/openmw-mp/Version.hpp
      sed -i "s|    if tes3mp.GetServerVersion() ~= .*|    if tes3mp.GetServerVersion() ~= \"$TARGET_VERSION_STRING\" then|g" "$KEEPERS"/PluginExamples/scripts/server.lua
    fi

    cd "$BASE"
  fi

    #PULL CODE CHANGES FROM THE GIT REPOSITORY
  if [ "$UPGRADE" == "YES" ]; then
    echo -e "\n>> Pulling code changes from git"
    cd "$CODE"
    git stash
    git pull
    git checkout master
    cd "$BASE"

    cd "$KEEPERS"/PluginExamples
    git stash
    git pull
    git checkout master
    cd "$BASE"
  fi

  echo -e "\n>> Doing a clean build of TES3MP"

  rm -r "$DEVELOPMENT"
  mkdir -p "$DEVELOPMENT"

  cd "$DEVELOPMENT"

  CMAKE_PARAMS="-DBUILD_OPENCS=OFF \
      -DCMAKE_CXX_STANDARD=14 \
      -DCMAKE_CXX_FLAGS=\"-std=c++14\" \
      -DCallFF_INCLUDES="${CALLFF_LOCATION}"/include \
      -DCallFF_LIBRARY="${CALLFF_LOCATION}"/build/src/libcallff.a \
      -DRakNet_INCLUDES="${RAKNET_LOCATION}"/include \
      -DRakNet_LIBRARY_DEBUG="${RAKNET_LOCATION}"/build/lib/libRakNetLibStatic.a \
      -DRakNet_LIBRARY_RELEASE="${RAKNET_LOCATION}"/build/lib/libRakNetLibStatic.a \
      -DTerra_INCLUDES="${TERRA_LOCATION}"/include \
      -DTerra_LIBRARY_RELEASE="${TERRA_LOCATION}"/lib/libterra.a"

  if [ $BUILD_OSG ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DOPENTHREADS_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOPENTHREADS_LIBRARY="${OSG_LOCATION}"/build/lib/libOpenThreads.so \
      -DOSG_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSG_LIBRARY="${OSG_LOCATION}"/build/lib/libosg.so \
      -DOSGANIMATION_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGANIMATION_LIBRARY="${OSG_LOCATION}"/build/lib/libosgAnimation.so \
      -DOSGDB_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGDB_LIBRARY="${OSG_LOCATION}"/build/lib/libosgDB.so \
      -DOSGFX_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGFX_LIBRARY="${OSG_LOCATION}"/build/lib/libosgFX.so \
      -DOSGGA_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGGA_LIBRARY="${OSG_LOCATION}"/build/lib/libosgGA.so \
      -DOSGPARTICLE_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGPARTICLE_LIBRARY="${OSG_LOCATION}"/build/lib/libosgParticle.so \
      -DOSGTEXT_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGTEXT_LIBRARY="${OSG_LOCATION}"/build/lib/libosgText.so\
      -DOSGUTIL_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGUTIL_LIBRARY="${OSG_LOCATION}"/build/lib/libosgUtil.so \
      -DOSGVIEWER_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGVIEWER_LIBRARY="${OSG_LOCATION}"/build/lib/libosgViewer.so"
  fi

  if [ $BUILD_BULLET ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DBullet_INCLUDE_DIR="${BULLET_LOCATION}"/install/include/bullet \
      -DBullet_BulletCollision_LIBRARY="${BULLET_LOCATION}"/install/lib/libBulletCollision.so \
      -DBullet_LinearMath_LIBRARY="${BULLET_LOCATION}"/install/lib/libLinearMath.so"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH":"${BULLET_LOCATION}"/install/lib
    export BULLET_ROOT="${BULLET_LOCATION}"/install
  fi

  if [ $SERVER_ONLY ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DBUILD_OPENMW_MP=ON \
      -DBUILD_BROWSER=OFF \
      -DBUILD_BSATOOL=OFF \
      -DBUILD_ESMTOOL=OFF \
      -DBUILD_ESSIMPORTER=OFF \
      -DBUILD_LAUNCHER=OFF \
      -DBUILD_MWINIIMPORTER=OFF \
      -DBUILD_MYGUI_PLUGIN=OFF \
      -DBUILD_OPENMW=OFF \
      -DBUILD_WIZARD=OFF"
  fi

  echo -e "\n\n$CMAKE_PARAMS\n\n"
  cmake "$CODE" $CMAKE_PARAMS
  set -o pipefail # so that the "tee" below would not make build always return success
  make -j $CORES 2>&1 | tee "${BASE}"/build.log

  cd "$BASE"

  #CREATE SYMLINKS FOR THE CONFIG FILES INSIDE THE NEW BUILD FOLDER
  echo -e "\n>> Creating symlinks of the config files in the build folder"
  for file in "$KEEPERS"/*.cfg
  do
    FILEPATH=$file
    FILENAME=$(basename $file)
    mv "$DEVELOPMENT/$FILENAME" "$DEVELOPMENT/$FILENAME.bkp" 2> /dev/null
    ln -s "$KEEPERS/$FILENAME" "$DEVELOPMENT/"
  done

  #CREATE SYMLINKS FOR RESOURCES INSIDE THE CONFIG FOLDER
  echo -e "\n>> Creating symlinks for resources inside the config folder"
  ln -s "$DEVELOPMENT"/resources "$KEEPERS"/resources 2> /dev/null

  #CREATE USEFUL SHORTCUTS ON THE BASE DIRECTORY
  echo -e "\n>> Creating useful shortcuts on the base directory"
  if [ $SERVER_ONLY ]; then
    SHORTCUTS=( "tes3mp-server" )
  else
    SHORTCUTS=( "tes3mp" "tes3mp-browser" "tes3mp-server" )
  fi
  for i in ${SHORTCUTS[@]}; do
    printf "#!/bin/bash\n\ncd build/\n./$i\ncd .." > "$i".sh
    chmod +x "$i".sh
  done

  #ALL DONE
  echo -e "\n\n\nAll done! Press any key to exit.\nMay Vehk bestow his blessing upon your Muatra."

fi

#MAKE PORTABLE PACKAGE
if [ $MAKE_PACKAGE ]; then
  echo -e "\n>> Creating TES3MP package"

  PACKAGE_BINARIES=("tes3mp" "tes3mp-browser" "tes3mp-server" "openmw-launcher" "openmw-wizard" "openmw-essimporter" "openmw-iniimporter" "bsatool" "esmtool")
  BLACKLISTED_LIBRARIES=("libc" "libdl" "ld-linux")

  #EXIT IF PATCHELF IS NOT INSTALLED
  which patchelf >/dev/null
  if [ $? -ne 0 ]; then
    echo -e "\nInstall \"patchelf\" before continuing"
    exit 1
  fi

  #EXIT IF TES3MP hasn't been compiled yet
  if [ ! -f "$DEVELOPMENT"/tes3mp ]; then
    echo -e "\nTES3MP has to be built before packaging"
    exit 1
  fi

  cp -r "$DEVELOPMENT" "$PACKAGE_TMP"
  cd "$PACKAGE_TMP"

  #CLEANUP UNNEEDED FILES
  echo -e "\nCleaning up unneeded files"
  find "$PACKAGE_TMP" -type d -name "CMakeFiles" -exec rm -r "{}" \;
  find "$PACKAGE_TMP" -type l -delete
  rm ./*.bkp

  #COPY USEFUL FILES
  echo -e "\nCopying useful files"
  cp -r "$KEEPERS"/{PluginExamples,*.cfg} .
  sed -i "s|home = .*|home = ./PluginExamples|g" "${PACKAGE_TMP}"/tes3mp-server-default.cfg

  #LIST AND COPY ALL LIBS
  mkdir -p libraries
  echo -e "\nCopying needed libraries"

  for BINARY in "${PACKAGE_BINARIES[@]}"; do
    #Exquisite and graceful method, copy only the non-system libs
    #join <(ldd "$BINARY" | awk '{if(substr($3,0,1)=="/") print $1,$3}') <(patchelf --print-needed "$BINARY" ) | cut -d\  -f2 | \
    #xargs -d '\n' -I{} cp --copy-contents {} ./libraries

    #Alternative and quite stupid method, copy everything
    ldd "$BINARY" | cut -d '>' -f2 | grep '^\s*/' | sed 's/^\s*//;s/\s*(.*$//' | cut -d ' ' -f 1 | \
    while read LIB; do
      echo -e "Copying library: $LIB"
      cp "$LIB" ./libraries
    done

  done

  #REMOVE BLACKLISTED LIBRARIES THAT SHOULDN'T BE RELATIVE
  echo -e "\nRemoving blacklisted libraries"
  for LIB in "${BLACKLISTED_LIBRARIES[@]}"; do
    rm "$PACKAGE_TMP"/libraries/*"$LIB"*
  done

  #PATCH LIBRARY PATHS ON THE EXECUTABLES
  #echo -e "\nPatching binary library paths"
  #for BINARY in "${PACKAGE_BINARIES[@]}"; do
  #  echo -e "Patching: $BINARY"
  #  patchelf --set-rpath "./libraries" "$PACKAGE_TMP"/"$BINARY"
  #done

  #CREATE WRAPPERS
  echo -e "\nCreating wrappers"
  for BINARY in "${PACKAGE_BINARIES[@]}"; do
    printf "#!/bin/bash\n\nLD_LIBRARY_PATH=\$LD_LIBRARY_PATH:./libraries ./$BINARY" > run_"$BINARY".sh
  done

  #PACKAGE INFO
  PACKAGE_ARCH=$(uname -m)
  PACKAGE_SYSTEM=$(uname -o  | sed 's,/,+,g')
  PACKAGE_DISTRO=$(lsb_release -si)
  PACKAGE_VERSION=$(cat "$CODE"/components/openmw-mp/Version.hpp | grep TES3MP_VERSION | awk -F'"' '{print $2}')
  PACKAGE_COMMIT=$(git --git-dir=$CODE/.git rev-parse @ | head -c10)
  PACKAGE_NAME="tes3mp-$PACKAGE_SYSTEM-$PACKAGE_ARCH-$PACKAGE_DISTRO-release-$PACKAGE_VERSION-$PACKAGE_COMMIT-$USER"
  PACKAGE_DATE="$(date +"%Y-%m-%d")"
  echo -e "TES3MP $PACKAGE_VERSION ($PACKAGE_COMMIT) built on $PACKAGE_SYSTEM $PACKAGE_ARCH ($PACKAGE_DISTRO) on $PACKAGE_DATE by $USER" > "$PACKAGE_TMP"/tes3mp-package-info.txt

  #CREATE ARCHIVE
  echo -e "\nCreating archive"
  mv "$PACKAGE_TMP" "$BASE"/TES3MP
  PACKAGE_TMP="$BASE"/TES3MP
  tar cvzf "$BASE"/package.tar.gz --directory="$BASE" TES3MP/

  #EXIT IF GOOF
  if [ $? -ne 0 ]; then
    echo -e "Failed to create package.\nExiting..."
    exit 1
  fi

  #RENAME ARCHIVE
  mv "$BASE"/package.tar.gz "$BASE"/"$PACKAGE_NAME".tar.gz

  #CLEANUP TEMPORARY FOLDER AND FINISH
  rm -rf "$PACKAGE_TMP"
  echo -e "\n>> Package created as \"$PACKAGE_NAME\""

  cd "$BASE"
fi

#UPGRADE THE TES3MP-DEPLOY SCRIPT
if [ $SCRIPT_UPGRADE ]; then

  SCRIPT_OLD_VERSION=$(cat tes3mp-deploy.sh | grep ^VERSION= | cut -d'"' -f2)

  if [ -d ./.git ]; then
    echo -e "\n>>Upgrading the TES3MP-deploy git repository"
    git pull
  else
    echo -e "\n>>Downloading TES3MP-deploy from GitHub"
    mv "$0" "$BASE"/.tes3mp-deploy.sh.bkp
    wget --no-verbose -O "$BASE"/tes3mp-deploy.sh https://raw.githubusercontent.com/GrimKriegor/TES3MP-deploy/master/tes3mp-deploy.sh
    chmod +x ./tes3mp-deploy.sh
  fi

  SCRIPT_NEW_VERSION=$(cat tes3mp-deploy.sh | grep ^VERSION= | cut -d'"' -f2)

  if [ "$SCRIPT_NEW_VERSION" == "" ]; then
    echo -e "\nThere was a problem downloading the script, exiting."
    exit 1
  fi

  if [ "$SCRIPT_OLD_VERSION" != "$SCRIPT_NEW_VERSION" ]; then
    echo -e "\nScript upgraded from ($SCRIPT_OLD_VERSION) to ($SCRIPT_NEW_VERSION)"
    exit 0
  else
    echo -e "\nScript already at the latest avaliable version ($SCRIPT_OLD_VERSION)"
    exit 0
  fi

fi
