DIST_REVISION=$1
DIST_SUFFIX=$2
DIST_LIBS=$3

DIST_NAME=1kdist

if [ "${DIST_REVISION}" != "" ]; then
    DIST_NAME="${DIST_NAME}_${DIST_REVISION}"
fi

if [ "${DIST_SUFFIX}" != "" ]; then
    DIST_NAME="${DIST_NAME}${DIST_SUFFIX}"
fi

DIST_NOTES=`pwd`/_1kiss.txt

DIST_ROOT=`pwd`/${DIST_NAME}
mkdir -p $DIST_ROOT

DIST_VERLIST=$DIST_ROOT/_1kiss.yml

# compile copy1k for script, non-recursive simple wildchard without error support
mkdir -p build
g++ -std=c++17 1k/copy1k.cpp -o build/copy1k
PATH=`pwd`/build:$PATH

# The dist flags
DISTF_WIN32=1
DISTF_WINRT=2
DISTF_WINALL=$(($DISTF_WIN32|$DISTF_WINRT))
DISTF_LINUX=4
DISTF_ANDROID=8
DISTF_MAC=16
DISTF_IOS=32
DISTF_TVOS=64
DISTF_WASM=128
DISTF_APPL=$(($DISTF_MAC|$DISTF_IOS|$DISTF_TVOS))
DISTF_NO_INC=1024
DISTF_NO_WINRT=$(($DISTF_WIN32|$DISTF_LINUX|$DISTF_ANDROID|$DISTF_APPL))
DISTF_NATIVES=$(($DISTF_WINALL|$DISTF_LINUX|$DISTF_ANDROID|$DISTF_APPL))
DISTF_ALL=$(($DISTF_NATIVES|$DISTF_WASM))

function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s/\r$//" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) >= 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

function try_copy_file {
    if [ -f "$1" ]; then
        cp "$1" "$2"
    fi
}

function dist_lib {
    LIB_NAME=$1
    DIST_DIR=$2
    DIST_FLAGS=$3
    CONF_HEADER=$4 # [optional]
    CONF_TEMPLATE=$5 # [optional]
    INC_DIR=$6 # [optional] such as: openssl/

    if [ $(($DIST_FLAGS & $DISTF_NO_INC)) = 0 ]; then
        # mkdir for commen
        mkdir -p ${DIST_DIR}/include

        # mkdir for platform spec config header file
        if [ "$CONF_TEMPLATE" = "config.h.in" ] ; then
            mkdir -p ${DIST_DIR}/include/win32/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/win64/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/linux/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/mac/${INC_DIR}
            # mkdir -p ${DIST_DIR}/include/ios-arm/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/ios-arm64/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/ios-x64/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/tvos-arm64/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/tvos-x64/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/android-arm/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/android-arm64/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/android-x86/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/android-x86_64/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/wasm/${INC_DIR}
        elif [ "$CONF_TEMPLATE" = "config_ab.h.in" ] ; then
            mkdir -p ${DIST_DIR}/include/win32/${INC_DIR}
            mkdir -p ${DIST_DIR}/include/unix/${INC_DIR}
        fi

        # copy common headers
        if [ ! $(($DIST_FLAGS & $DISTF_MAC)) = 0 ]; then
            cp -rf install_osx_x64/${LIB_NAME}/include/${INC_DIR} ${DIST_DIR}/include/${INC_DIR}
        elif [ ! $(($DIST_FLAGS & $DISTF_WINALL)) = 0 ]; then
            cp -rf install_win32_x64/${LIB_NAME}/include/${INC_DIR} ${DIST_DIR}/include/${INC_DIR}
        fi

        if [ "$CONF_HEADER" != "" ] ; then
            rm -rf ${DIST_DIR}/include/${INC_DIR}${CONF_HEADER}

            CONF_CONTENT=$(cat 1k/$CONF_TEMPLATE)
            STYLED_LIB_NAME=${LIB_NAME//-/_}
            CONF_CONTENT=${CONF_CONTENT//@LIB_NAME@/$STYLED_LIB_NAME}
            CONF_CONTENT=${CONF_CONTENT//@INC_DIR@/$INC_DIR}
            CONF_CONTENT=${CONF_CONTENT//@CONF_HEADER@/$CONF_HEADER}
            echo "$CONF_CONTENT" >> ${DIST_DIR}/include/${INC_DIR}${CONF_HEADER}

            # copy platform spec config header file
            if [ "$CONF_TEMPLATE" = "config.h.in" ] ; then
                cp install_win32_x86/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/win32/${INC_DIR}
                cp install_win32_x64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/win64/${INC_DIR}
                cp install_linux_x64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/linux/${INC_DIR}
                cp install_osx_x64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/mac/${INC_DIR}
                # cp install_ios_armv7/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/ios-arm/${INC_DIR}
                cp install_ios_arm64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/ios-arm64/${INC_DIR}
                cp install_ios_x64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/ios-x64/${INC_DIR}
                cp install_tvos_arm64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/tvos-arm64/${INC_DIR}
                cp install_tvos_x64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/tvos-x64/${INC_DIR}
                cp install_android_armv7/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/android-arm/${INC_DIR}
                cp install_android_arm64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/android-arm64/${INC_DIR}
                cp install_android_x86/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/android-x86/${INC_DIR}
                cp install_android_x64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/android-x86_64/${INC_DIR}
                try_copy_file install_wasm/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/wasm/${INC_DIR}

            elif [ "$CONF_TEMPLATE" = "config_ab.h.in" ] ; then
                cp install_win32_x86/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/win32/${INC_DIR}
                cp install_linux_x64/${LIB_NAME}/include/${INC_DIR}${CONF_HEADER} ${DIST_DIR}/include/unix/${INC_DIR}
            fi
        fi
    fi

    # create lib dirs
    if [ $(($DIST_FLAGS & $DISTF_WIN32)) != 0 ]; then
        mkdir -p ${DIST_DIR}/lib/win32/x86
        copy1k "install_win32_x86/${LIB_NAME}/lib/*.lib" ${DIST_DIR}/lib/win32/x86/
        copy1k "install_win32_x86/${LIB_NAME}/bin/*.dll" ${DIST_DIR}/lib/win32/x86/

        mkdir -p ${DIST_DIR}/lib/win32/x64
        copy1k "install_win32_x64/${LIB_NAME}/lib/*.lib" ${DIST_DIR}/lib/win32/x64/
        copy1k "install_win32_x64/${LIB_NAME}/bin/*.dll" ${DIST_DIR}/lib/win32/x64/
    fi

    if [ $(($DIST_FLAGS & $DISTF_WINRT)) != 0 ]; then
        mkdir -p ${DIST_DIR}/lib/winrt/x64
        copy1k "install_winrt_x64/${LIB_NAME}/lib/*.lib" ${DIST_DIR}/lib/winrt/x64/
        copy1k "install_winrt_x64/${LIB_NAME}/bin/*.dll" ${DIST_DIR}/lib/winrt/x64/

        mkdir -p ${DIST_DIR}/lib/winrt/arm64
        copy1k "install_winrt_arm64/${LIB_NAME}/lib/*.lib" ${DIST_DIR}/lib/winrt/arm64/
        copy1k "install_winrt_arm64/${LIB_NAME}/bin/*.dll" ${DIST_DIR}/lib/winrt/arm64/
    fi

    if [ $(($DIST_FLAGS & $DISTF_LINUX)) != 0 ]; then
        mkdir -p ${DIST_DIR}/lib/linux
        copy1k "install_linux_x64/${LIB_NAME}/lib/*.a" ${DIST_DIR}/lib/linux/
        copy1k "install_linux_x64/${LIB_NAME}/lib/*.so" ${DIST_DIR}/lib/linux/
    fi

    if [ $(($DIST_FLAGS & $DISTF_ANDROID)) != 0 ]; then
        mkdir -p ${DIST_DIR}/lib/android/armeabi-v7a
        mkdir -p ${DIST_DIR}/lib/android/arm64-v8a
        mkdir -p ${DIST_DIR}/lib/android/x86
        mkdir -p ${DIST_DIR}/lib/android/x86_64
        cp install_android_armv7/${LIB_NAME}/lib/*.a ${DIST_DIR}/lib/android/armeabi-v7a/
        cp install_android_arm64/${LIB_NAME}/lib/*.a ${DIST_DIR}/lib/android/arm64-v8a/
        cp install_android_x86/${LIB_NAME}/lib/*.a ${DIST_DIR}/lib/android/x86/
        cp install_android_x64/${LIB_NAME}/lib/*.a ${DIST_DIR}/lib/android/x86_64/
    fi

    if [ $(($DIST_FLAGS & $DISTF_WASM)) != 0 ] ; then
        mkdir -p ${DIST_DIR}/lib/wasm
        copy1k "install_wasm/${LIB_NAME}/lib/*.a" ${DIST_DIR}/lib/wasm/
        copy1k "install_wasm/${LIB_NAME}/lib/*.so" ${DIST_DIR}/lib/wasm/
    fi

    if [ $(($DIST_FLAGS & $DISTF_MAC)) != 0 ]; then
        mkdir -p ${DIST_DIR}/lib/mac
    fi

    if [ $(($DIST_FLAGS & $DISTF_IOS)) != 0 ]; then
        mkdir -p ${DIST_DIR}/lib/ios
    fi

    if [ $(($DIST_FLAGS & $DISTF_TVOS)) != 0 ]; then
        mkdir -p ${DIST_DIR}/lib/tvos
    fi

    ver=
    branch=
    commits=
    rev=
    verinfo_file=

    if [ -f "install_win32_x64/${LIB_NAME}/_1kiss" ] ; then
        verinfo_file="install_win32_x64/${LIB_NAME}/_1kiss"
    elif [ -f "install_osx_x64/${LIB_NAME}/_1kiss" ] ; then
        verinfo_file="install_osx_x64/${LIB_NAME}/_1kiss"
    elif [ -f "install_linux_x64/${LIB_NAME}/_1kiss" ] ; then
        verinfo_file="install_linux_x64/${LIB_NAME}/_1kiss"
    fi

    echo "verinfo_file=$verinfo_file"

    if [ "$verinfo_file" != "" ] ; then
        eval $(parse_yaml "$verinfo_file")
        if [ "$ver" != "" ] ; then
            echo "$LIB_NAME: $ver" >> "$DIST_VERLIST"
            echo "- $LIB_NAME: $ver" >> "$DIST_NOTES"
        else
           if [ "$branch" != "" ] && [ "$branch" != "master" ] ; then
               eval $(parse_yaml "src/${LIB_NAME}/build.yml")
               if [ "$ver" != "" ] ; then
                  echo "$LIB_NAME: $ver-$rev" >> "$DIST_VERLIST"
                  echo "- $LIB_NAME: $ver-$rev" >> "$DIST_NOTES"
               else
                  echo "$LIB_NAME: $branch-$rev" >> "$DIST_VERLIST"
                  echo "- $LIB_NAME: $branch-$rev" >> "$DIST_NOTES"
               fi
           else
               echo "$LIB_NAME: git $rev" >> "$DIST_VERLIST"
               echo "- $LIB_NAME: git $rev" >> "$DIST_NOTES"
           fi
        fi
    else
        # read version from src/${LIB_NAME}/build.yml
        eval $(parse_yaml "src/${LIB_NAME}/build.yml")
        echo "$LIB_NAME: $ver" >> "$DIST_VERLIST"
        echo "- $LIB_NAME: $ver" >> "$DIST_NOTES"
    fi
}

# dist libs
if [ "$DIST_LIBS" = "" ] ; then
    DIST_LIBS="zlib,jpeg-turbo,openssl,cares,curl,luajit,angle"
fi

if [ -f "$DIST_VERLIST" ] ; then
    rm -f "$DIST_VERLIST"
fi

libs_arr=(${DIST_LIBS//,/ })
libs_count=${#libs_arr[@]}
echo "Dist $libs_count libs ..."
mkdir ./seprate
for (( i=0; i<${libs_count}; ++i )); do
  lib_name=${libs_arr[$i]}
  source src/$lib_name/dist1.sh $DIST_ROOT
  cd ${DIST_NAME}
  zip -q -r ../seprate/$lib_name.zip ./$lib_name
  cd ..
done

ls ./seprate/

# create dist package
# DIST_PACKAGE=${DIST_NAME}.zip
# zip -q -r ${DIST_PACKAGE} ${DIST_NAME}

# Export DIST_NAME & DIST_PACKAGE for uploading
if [ "$GITHUB_ENV" != "" ] ; then
    echo "DIST_NAME=$DIST_NAME" >> $GITHUB_ENV
    # echo "DIST_PACKAGE=${DIST_PACKAGE}" >> $GITHUB_ENV
    echo "DIST_NOTES=${DIST_NOTES}" >> $GITHUB_ENV
    echo "DIST_VERLIST=${DIST_VERLIST}" >> $GITHUB_ENV
fi
