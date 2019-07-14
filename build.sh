#!/usr/bin/env bash

UNAME=$(uname -s)
if [[ $UNAME == *"MINGW"* ]]; then
  suffix=".dll"
  if [[ $UNAME == *"MINGW64"* ]]; then
    mingw_prefix="mingw64"
  else
    mingw_prefix="mingw32"
  fi
elif [[ $UNAME == "Darwin" ]]; then
  suffix=".dylib"
else
  suffix=".so"
fi

install_dir=$PWD/mupen64plus
mkdir -p $install_dir
base_dir=$PWD

cd $base_dir/mupen64plus-core/projects/unix
make -j$(nproc) all NEW_DYNAREC=1
cp -P $base_dir/mupen64plus-core/projects/unix/*$suffix* $install_dir
cp $base_dir/mupen64plus-core/data/* $install_dir

cd $base_dir/mupen64plus-rsp-hle/projects/unix
make -j$(nproc) all
cp $base_dir/mupen64plus-rsp-hle/projects/unix/*$suffix $install_dir

cd $base_dir/mupen64plus-input-sdl/projects/unix
make -j$(nproc) all
cp $base_dir/mupen64plus-input-sdl/projects/unix/*$suffix $install_dir
cp $base_dir/mupen64plus-input-sdl/data/* $install_dir

cd $base_dir/mupen64plus-audio-sdl2/projects/unix
make -j$(nproc) all
cp $base_dir/mupen64plus-audio-sdl2/projects/unix/*$suffix $install_dir

mkdir -p $base_dir/mupen64plus-gui/build
cd $base_dir/mupen64plus-gui/build
if [[ $UNAME == *"MINGW"* ]]; then
  qmake ../mupen64plus-gui.pro
  make -j$(nproc) release
  cp $base_dir/mupen64plus-gui/build/release/mupen64plus-gui.exe $install_dir
elif [[ $UNAME == "Darwin" ]]; then
  /usr/local/Cellar/qt5/*/bin/qmake ../mupen64plus-gui.pro
  make -j$(nproc)
  cp -Rp $base_dir/mupen64plus-gui/build/mupen64plus-gui.app $install_dir
else
  qmake ../mupen64plus-gui.pro
  make -j$(nproc)
  cp $base_dir/mupen64plus-gui/build/mupen64plus-gui $install_dir
fi

cd $base_dir/GLideN64/src
./getRevision.sh

mkdir -p $base_dir/GLideN64/src/GLideNUI/build
cd $base_dir/GLideN64/src/GLideNUI/build
if [[ $UNAME == *"MINGW"* ]]; then
  qmake ../GLideNUI.pro
  make -j$(nproc) release
elif [[ $UNAME == "Darwin" ]]; then
  /usr/local/Cellar/qt5/*/bin/qmake ../GLideNUI.pro
  make -j$(nproc)
else
  qmake ../GLideNUI.pro
  make -j$(nproc)
fi

cd $base_dir/GLideN64/projects/cmake
sed -i 's/GLideNUI\/build\/debug\/libGLideNUI.a/GLideNUI\/build\/release\/libGLideNUI.a/g' ../../src/CMakeLists.txt
if [[ $UNAME == *"MINGW"* ]]; then
  sed -i 's/check_ipo_supported(RESULT result)//g' ../../src/CMakeLists.txt
  # Workaround a MSYS2 packaging issue for Qt5 (see https://github.com/msys2/MINGW-packages/issues/5253)
  sed -i -e 's/C:\/building\/msys32/C:\/msys64/g' /$mingw_prefix/lib/cmake/Qt5Gui/Qt5GuiConfigExtras.cmake
  cmake -G "MSYS Makefiles" -DVEC4_OPT=On -DCRC_OPT=On -DMUPENPLUSAPI=On ../../src/
else
  rm -rf ../../src/GLideNHQ/inc
  cmake -DUSE_SYSTEM_LIBS=On -DVEC4_OPT=On -DCRC_OPT=On -DMUPENPLUSAPI=On ../../src/
fi
make -j$(nproc)

if [[ $UNAME == *"MINGW"* ]]; then
  cp mupen64plus-video-GLideN64$suffix $install_dir
else
  cp plugin/Release/mupen64plus-video-GLideN64$suffix $install_dir
fi
cp $base_dir/GLideN64/ini/GLideN64.custom.ini $install_dir

cd $base_dir

strip $install_dir/*$suffix

if [[ $UNAME == *"MINGW"* ]]; then
  if [[ $UNAME == *"MINGW64"* ]]; then
    my_os=win64
  else
    my_os=win32
  fi
  
  copyDlls(){
	local dlls=`objdump.exe -p $1 | grep 'DLL Name:' | sed -e "s/\t*DLL Name: //g"`
	while read -r filename; do
	  local dependency="/$mingw_prefix/bin/$filename"
	  if [ -f $dependency ] && [ ! -f "$install_dir/$filename" ]; then
		cp $dependency $install_dir
		echo "Copied $dependency"
		copyDlls $dependency
	  fi
	done <<< "$dlls"
  }
  
  while read -r bin; do
    echo "Dependencies for $bin"
    copyDlls "$bin"
  done <<< "$(ls $install_dir/*.{dll,exe})"
  
  cp $base_dir/7za.exe $install_dir
  
  cd $install_dir
  windeployqt ./mupen64plus-gui.exe
  cd $base_dir
  
  while read -r bin; do
    echo "Dependencies for $bin"
    copyDlls "$bin"
  done <<< "$(ls $install_dir/**/*.{dll,exe})"
elif [[ $UNAME == "Darwin" ]]; then
  my_os=macos

  find mupen64plus -type f -depth 1 \
    -exec mv {} mupen64plus/mupen64plus-gui.app/Contents/MacOS/ \;

  cd $install_dir
  /usr/local/Cellar/qt5/*/bin/macdeployqt mupen64plus-gui.app

  for P in $(find mupen64plus-gui.app -type f -name 'Qt*'; find mupen64plus-gui.app -type f -name '*.dylib'); do
    for P1 in $(otool -L $P | awk '/\/usr\/local\/Cellar/ {print $1}'); do
      PATHNAME=$(echo $P1 | awk '{sub(/(\/Qt.+\.framework|[^\/]*\.dylib).*/, ""); print}')
      PSLASH1=$(echo $P1 | sed "s,$PATHNAME,@executable_path/../Frameworks,g")
      install_name_tool -change $P1 $PSLASH1 $P
    done
  done

  cd $base_dir
else
  if [[ $HOST_CPU == "i686" ]]; then
    my_os=linux32
  else
    my_os=linux64
  fi
fi

zip -r mupen64plus-GLideN64-$my_os.zip mupen64plus
