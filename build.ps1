# $target_os = $args[0]
# $target_cpu = $args[1]
# $libs = $args[2]
param(
    [Alias('p')]
    $target_os,
    [Alias('a')]
    $target_cpu,
    $libs,
    $sdk = '',
    [switch]$rebuild
)

Set-Alias println Write-Host

function mkdirs($path) {
    if (!(Test-Path $path -PathType Container)) {
        New-Item $path -ItemType Directory 1>$null 2>$null
    }
}

# determine build lib list
if (!$libs) {
    $libs = @(
        'zlib'
        'openssl'
        'cares'
        'curl'
        'jpeg-turbo'
        'luajit'
        'angle'
    )
} else {
    if($libs -isnot [array]) { # not array, split by ','
        $libs = $libs -split ","
    }
}
Write-Output "building $($libs.Count) libs ...", $libs

$_1k_root = $PSScriptRoot
println "1kiss: _1k_root=$_1k_root"

println "1kiss: env:NO_DLL=$env:NO_DLL"

if ($target_cpu -eq 'amd64_arm64') {
    $target_cpu = 'arm64'
}

$build_script = Join-Path "$_1k_root" "1k/build.ps1"
$fetch_script = Join-Path "$_1k_root" "1k/fetch.ps1"
$build_src = Join-Path $_1k_root "buildsrc"
$install_path = "install_${target_os}"

if ($target_cpu -ne '*') {
    $install_path = "${install_path}_$target_cpu"
}
if($sdk.StartsWith('sim')) { $install_path += '_sim' }
$install_root = Join-Path $_1k_root $install_path

# Create buildsrc tmp dir for build libs
mkdirs $build_src

# import yaml parser
if ((Get-Module -ListAvailable -Name powershell-yaml) -eq $null) {
    Install-Module -Name powershell-yaml -Force -Repository PSGallery -Scope CurrentUser
}

$forward_args = @{}
if($rebuild) {
    $forward_args['rebuild'] = $true
}
if($sdk) {
    $forward_args['sdk'] = $sdk
}

. $build_script -p $target_os -a $target_cpu @forward_args -setupOnly -ndkOnly
setup_nasm

if ($IsWin) {
    #relocate powershell.exe to opensource edition pwsh.exe to solve angle gclient execute issues:
    # Get-FileHash is not recognized as a name of a cmdlet
    $pwshPath = $(Get-Command pwsh).Path
    $pwshDir =  Split-Path -Path $pwshPath

    echo "Before relocate powershell"
    powershell -Command {$pwshVSI='PowerShell ' + $PSVersionTable.PSVersion.ToString();echo $pwshVSI}

    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    Copy-Item "$pwshDir\pwsh.exe" "$pwshDir\powershell.exe"
    $ErrorActionPreference = $eap

    $env:Path = "$pwshPath;$env:Path"
    echo "After relocate powershell"
    powershell -Command {$pwshVSI='PowerShell ' + $PSVersionTable.PSVersion.ToString();echo $pwshVSI}
}

if ($Global:is_android) {
    active_ndk_toolchain
    $Global:android_api_level = @{arm64 = 21; x64 = 22; armv7 = 16; x86 = 16}[$target_cpu]
}
elseif ($is_darwin_family) {
    # query xcode version
    $xcode_ver_str = xcodebuild -version | Select-Object -First 1
    if ($xcode_ver_str) {
        $matchInfo = [Regex]::Match($xcode_ver_str, '(\d+\.)+(\*|\d+)(\-[a-z]+[0-9]*)?')
        $Global:XCODE_VERSION = $matchInfo.Value
    }

    if (!$Global:XCODE_VERSION) {
        throw "1kiss: query XCODE_VERSION fail"
    }

    println "1kiss: XCODE_VERSION=$Global:XCODE_VERSION"

    # require xcutils.ps1 for xcode_get_sdkname
    . $(Join-Path $_1k_root '1k/xcutils.ps1')
}

mkdirs $install_root

# options_xxx, xxx = msw, unix, embed
$embed_family = ''
if ($is_win_family) {
    $os_family = 'msw'
}
else {
    $os_family = 'unix'
    if ($Global:is_ios -or $Global:is_tvos -or $Global:is_android) {
        $embed_family = 'embed'
    }
}

$darwin_family = ''
if ($is_darwin_family) {
    $darwin_family = 'darwin'
}

Foreach ($lib_name in $libs) {
    $build_conf_path = Join-Path $_1k_root "src/$lib_name/build.yml"
    $build_conf = ConvertFrom-Yaml -Yaml (Get-Content $build_conf_path -raw)
    if ($build_conf.targets -and !$build_conf.targets.contains($target_os)) {
        println "Skip build $lib_name which is not allow for target: $target_os"
        continue
    }
    
    if ($build_conf.archs -and !$build_conf.archs.contains($target_os)) {
        println "Skip build $lib_name which is not allow for arch: $target_os"
        continue
    }
    
    # fetch repo, return variable: $lib_src
    $rel_script = Join-Path $_1k_root "src/$lib_name/rel1.ps1"
    $version = $build_conf.ver
    $revision = $null # commit_hash
    if (Test-Path $rel_script -PathType Leaf) {
        $version,$revision = &$rel_script $build_conf.ver
    } else {
        $revision = "$($build_conf.tag_prefix)$version"
        if ($build_conf.tag_dot2ul) {
            $revision = $revision.Replace('.', '_')
        }
    }

    $is_gn = $build_conf.cb_tool -eq 'gn'
    if ($is_gn) {
        setup_gclient
    }
    . $fetch_script -uri $build_conf.repo -ver $version -rev $revision -prefix $build_src -name $lib_name

    # preprocess $build_conf.options
    if ($build_conf.options) {
        $build_conf.options = (eval $build_conf.options).Split(' ')
    }
    else {
        $build_conf.options = @()
    }

    if (!$is_host_target -and $build_conf.options_cross) {
        $build_conf.options += (eval $build_conf.options_cross).Split(' ')
    }
    
    if ($build_conf."options_$os_family") {
        $build_conf.options += (eval $build_conf."options_$os_family") -split ' '
    }
    if ($build_conf."options_$embed_family") {
        $build_conf.options += (eval $build_conf."options_$embed_family") -split ' '
    }
    if ($build_conf."options_$darwin_family") {
        $build_conf.options += (eval $build_conf."options_$darwin_family") -split ' '
    }
    if ($build_conf."options_$target_os") {
        $build_conf.options += (eval $build_conf."options_$target_os") -split ' '
    }
    println "Building $lib_name in $lib_src..."
    println "build_conf.options: $($build_conf.options)"
    # patch before build
    $patch_script = Join-Path $_1k_root "src/$lib_name/patch1.ps1"
    if (Test-Path $patch_script -PathType Leaf) {
        &$patch_script $lib_src
    }

    # build
    Push-Location $lib_src
    $install_dir = Join-Path $install_root $lib_name
    mkdirs $install_dir
    if ($build_conf.cb_tool -ne 'custom') {
        $_config_options = $build_conf.options
        if ($build_conf.cb_tool -eq 'cmake') {
            if ($is_winrt) {
                $_config_options += "-DCMAKE_VS_WINDOWS_TARGET_PLATFORM_MIN_VERSION=$env:VS_DEPLOYMENT_TARGET"
            }

            if (!$is_win_family) {
                $_config_options += '-DCMAKE_C_FLAGS=-fPIC'
            }

            $_config_options += "-DCMAKE_INSTALL_PREFIX=$install_dir"
        
            &$build_script -p $target_os -a $target_cpu -xc $_config_options -xb '--target', 'install' @forward_args
        } elseif($is_gn) {
            &$build_script -p $target_os -a $target_cpu -xc $_config_options -xt 'gn' -t "$($build_conf.cb_target)" @forward_args
        } else {
            throw "Unsupported cross build tool: $($build_conf.cb_tool)"
        }
    }
    else {
        $custom_build_script = Join-Path $_1k_root "src/$lib_name/build1.ps1"
        . $custom_build_script $target_os $target_cpu $install_dir @forward_args
    }
    Pop-Location

    # custom install step
    $install_script = Join-Path $_1k_root "src/$lib_name/install1.ps1"
    if (Test-Path $install_script) {
        &$install_script $install_dir $lib_src
    }
    # clean unnecessary files
    $clean_script = Join-Path $_1k_root "src/$lib_name/clean1.ps1"
    if (Test-Path $clean_script -PathType Leaf) {
        &$clean_script $install_dir
    }

    # install version file
    $version_file = Join-Path $lib_src '_1kiss'
    if (Test-Path $version_file -PathType Leaf) {
        Copy-Item $version_file $install_dir
    }

    # delete lib_src if run in github ci
    if ($is_gh_act) {
        println "Deleting $lib_src"
        Remove-Item $lib_src -Recurse -Force
    }
}

# Export INSTALL_ROOT for uploading
if ($is_gh_act) {
    Write-Output "install_path=$install_path" >> $env:GITHUB_ENV
}
