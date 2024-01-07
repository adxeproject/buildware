$target_os = $args[0]
$target_arch = $args[1]
$install_dir = $args[2]

$CONFIG_ALL_OPTIONS = $build_conf.options
$TARGET_OPTIONS = @()


$env:CFLAGS = $null
$env:LDFLAGS = $null
$env:CC = $null
$env:CXX = $null

if ($target_os.StartsWith('win')) {
    # require preinstalled perl interpreter: https://strawberryperl.com/releases.html
    if ($target_arch -eq "x86") {
        if (!$is_winrt) {
            $TARGET_OPTIONS += 'VC-WIN32'
        }
        else {
            $TARGET_OPTIONS += 'VC-WIN32-UWP'
        }
    }
    else {
        if (!$is_winrt) {
            $TARGET_OPTIONS += 'VC-WIN64A'
        }
        else {
            if ($target_arch -eq 'x64') {
                $TARGET_OPTIONS += 'VC-WIN64A-UWP'
            }
            elseif ($target_arch -eq 'arm64') {
                $TARGET_OPTIONS += 'VC-WIN64-ARM-UWP'
            }
            else {
                Write-Output "Unsupported arch: $target_arch"
                return 1
            }
        }
    }

    if ($env:NO_DLL -eq 'true') {
        $CONFIG_ALL_OPTIONS += "no-shared"
    }
}
else {
    $target_uarch = if ($target_arch -eq 'x64') { 'x86_64' } else { $target_arch }
    
    if ($target_os -eq 'osx') {
        $TARGET_OPTIONS += "darwin64-$target_uarch-cc"
    }
    elseif ($target_os -eq 'ios' -or $target_os -eq 'tvos') {
        # Export OPENSSL_LOCAL_CONFIG_DIR for perl script file 'openssl/Configure' 
        $env:OPENSSL_LOCAL_CONFIG_DIR = Join-Path $_1k_root '1k' 

        $ios_plat_suffix = 'OS'
        if ( $target_arch -eq 'x64' ) {
            # asume x64 as simulator
            $TARGET_OPTIONS += "ios-sim-cross-$target_uarch"
            $ios_plat_suffix = 'Simulator'
        }
        else {
            $TARGET_OPTIONS += "ios-cross-$target_arch"
        }

        $IOS_PLAT = if ($target_os -eq 'ios') { "iPhone${ios_plat_suffix}" } else { "AppleTV${ios_plat_suffix}" }
        
        $env:CROSS_TOP = "$(xcode-select -print-path)/Platforms/$IOS_PLAT.platform/Developer"
        $env:CROSS_SDK = "$IOS_PLAT.sdk"
    }
    elseif ($target_os -eq 'android') {
        if ($target_uarch.EndsWith('v7')) { $target_uarch = $target_uarch.TrimEnd('v7') }
        $TARGET_OPTIONS += "android-$target_uarch"
        $TARGET_OPTIONS += "-D__ANDROID_API__=$android_api_level"
        if ( $target_arch -eq "x86" ) {
            $TARGET_OPTIONS += '-latomic'
        }
    }
    elseif ($target_os -eq 'wasm') {
        $env:CFLAGS = '-pthread -O3'
        $env:LDFLAGS = "-s FILESYSTEM=1 -s INVOKE_RUN=0` -s USE_ES6_IMPORT_META=0 -pthread"
        $env:CC = 'emcc'
        $env:CXX = 'emcc'
    }
}

$CONFIG_ALL_OPTIONS += $TARGET_OPTIONS
$CONFIG_ALL_OPTIONS += "--prefix=$install_dir", "--openssldir=$install_dir"
Write-Output ("CONFIG_ALL_OPTIONS=$CONFIG_ALL_OPTIONS, Count={0}" -f $CONFIG_ALL_OPTIONS.Count)

if ($target_os.StartsWith('win')) {
    perl Configure $CONFIG_ALL_OPTIONS
    perl configdata.pm --dump
    nmake install_sw
}
else {
    if ($target_os -ne 'wasm') {
        if (!(Test-Path Makefile -PathType Leaf)) {
            if ( $target_os -eq "linux" ) {
                ./config $CONFIG_ALL_OPTIONS && perl configdata.pm --dump
            }
            else {
                ./Configure $CONFIG_ALL_OPTIONS && perl configdata.pm --dump
            }
        }
        make VERBOSE=1
        make install_sw
    }
    else {
        if (!(Test-Path Makefile -PathType Leaf)) {
            emconfigure ./Configure $CONFIG_ALL_OPTIONS
        }
        perl configdata.pm --dump
        # remove incorrect use of CROSS_COMPILE
        sed -i 's/$(CROSS_COMPILE)//' Makefile
        emmake make VERBOSE=1
        emmake make install_sw
    }
}

$Global:openssl_dir = $install_dir
