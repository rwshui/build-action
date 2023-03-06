#!/bin/bash -eux
RELEASE_TAG=$(basename ${GITHUB_REF})
APP_NAME="unknown"
BUILD_TARGET="linux/amd64"
ldflags="\
  -w -s \
  -X 'github.com/libsgh/${APP_NAME}/module.VERSION=${RELEASE_TAG}' \
  -X 'github.com/libsgh/${APP_NAME}/module.BUILD_TIME=$(date "+%F %T")' \
  -X 'github.com/libsgh/${APP_NAME}/module.GO_VERSION=$(go version)' \
  -X 'github.com/libsgh/${APP_NAME}/module.GIT_COMMIT_SHA=$(git show -s --format=%H)' \
  "
GET_NEW_VERSION ()
{
  LatestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
  LatestTag=${LatestTag:1}
  declare -a part=( ${LatestTag//\./ } )
  declare    new
  declare -i carry=1

  for (( CNTR=${#part[@]}-1; CNTR>=0; CNTR-=1 )); do
    len=${#part[CNTR]}
    new=$((part[CNTR]+carry))
    [ ${#new} -gt $len ] && carry=1 || carry=0
    [ $CNTR -gt 0 ] && part[CNTR]=${new: -len} || part[CNTR]=${new}
  done
  new="${part[*]}"
  RELEASE_TAG="v${new// /.}"
}
BUILD(){
  cd ${GITHUB_WORKSPACE}
  xgo --targets=linux/* -out ${APP_NAME} -ldflags="$ldflags" .
  xgo --targets=darwin/* -out ${APP_NAME} -ldflags="$ldflags" .
  xgo --targets=windows/* -out ${APP_NAME} -ldflags="$ldflags -H windowsgui" .
  mkdir -p ${GITHUB_WORKSPACE}/dist/compress
  mv ${APP_NAME}-* dist
  cd dist
  upx -9 ./${APP_NAME}-linux*
  upx -9 ./${APP_NAME}-windows*
}

NIGHTLY_BUILD() {
  GET_NEW_VERSION
  d=$(date "+%m%d%H%M")
  flags="\
    -w -s \
    -X 'github.com/libsgh/${APP_NAME}/module.VERSION=${RELEASE_TAG}.${d}' \
    -X 'github.com/libsgh/${APP_NAME}/module.BUILD_TIME=$(date "+%F %T")' \
    -X 'github.com/libsgh/${APP_NAME}/module.GO_VERSION=$(go version)' \
    -X 'github.com/libsgh/${APP_NAME}/module.GIT_COMMIT_SHA=$(git show -s --format=%H)' \
    "
  cd ${GITHUB_WORKSPACE}
  target_flag=$(echo $BUILD_TARGET | grep "windows")
  if [[ "$target_flag" != "" ]]
  then
      xgo --targets="$BUILD_TARGET" -out ${APP_NAME} -ldflags="$flags -H windowsgui" .
  else
      xgo --targets="$BUILD_TARGET" -out ${APP_NAME}  -ldflags="$flags" .
  fi
  mkdir -p ${GITHUB_WORKSPACE}/dist
  mv ${APP_NAME}-* dist
  cd dist
  upx -9 ./${APP_NAME}-*
  cd ${GITHUB_WORKSPACE}
  cp -r LICENSE README.md ${GITHUB_WORKSPACE}/dist
}

NIGHTLY_UI_BUILD() {
  cd ${GITHUB_WORKSPACE}
  mkdir -p ${GITHUB_WORKSPACE}/dist/ui
  cp -R -f static/ ${GITHUB_WORKSPACE}/dist/ui/static/
  cp -R -f templates/ ${GITHUB_WORKSPACE}/dist/ui/templates/
}

BUILD_DOCKER() {
  go build -o ./bin/${APP_NAME} -ldflags="$ldflags" .
}

NIGHTLY_BUILD_DOCKER() {
  GET_NEW_VERSION
  d=$(date "+%m%d%H%M")
  flags="\
      -w -s \
      -X 'github.com/libsgh/${APP_NAME}/module.VERSION=${RELEASE_TAG}.${d}' \
      -X 'github.com/libsgh/${APP_NAME}/module.BUILD_TIME=$(date "+%F %T")' \
      -X 'github.com/libsgh/${APP_NAME}/module.GO_VERSION=$(go version)' \
      -X 'github.com/libsgh/${APP_NAME}/module.GIT_COMMIT_SHA=$(git show -s --format=%H)' \
      "
  go build -o ./bin/${APP_NAME} -ldflags="$flags" .
}

BUILD_MUSL(){
  cd ${GITHUB_WORKSPACE}
  BASE="https://musl.noki.workers.dev/"
  FILES=(x86_64-linux-musl-cross aarch64-linux-musl-cross arm-linux-musleabihf-cross mips-linux-musl-cross mips64-linux-musl-cross mips64el-linux-musl-cross mipsel-linux-musl-cross powerpc64le-linux-musl-cross s390x-linux-musl-cross)
  for i in "${FILES[@]}"; do
    url="${BASE}${i}.tgz"
    curl -L -o "${i}.tgz" "${url}"
    sudo tar xf "${i}.tgz" --strip-components 1 -C /usr/local
  done
  OS_ARCHES=(linux-musl-amd64 linux-musl-arm64 linux-musl-arm linux-musl-mips linux-musl-mips64 linux-musl-mips64le linux-musl-mipsle linux-musl-ppc64le linux-musl-s390x)
  CGO_ARGS=(x86_64-linux-musl-gcc aarch64-linux-musl-gcc arm-linux-musleabihf-gcc mips-linux-musl-gcc mips64-linux-musl-gcc mips64el-linux-musl-gcc mipsel-linux-musl-gcc powerpc64le-linux-musl-gcc s390x-linux-musl-gcc)
  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc=${CGO_ARGS[$i]}
    echo building for ${os_arch}
    CGO_ENABLED=1 GOOS=${os_arch%%-*} GOARCH=${os_arch##*-} CC=${cgo_cc} go build -o ${GITHUB_WORKSPACE}/dist/${APP_NAME}-$os_arch -ldflags="$ldflags" -tags=jsoniter .
  done
  mkdir -p ${GITHUB_WORKSPACE}/dist/compress
}

COMPRESS_UI(){
  cd ${GITHUB_WORKSPACE}
  mkdir ui
  cp -R -f static/ ui/static/
  cp -R -f templates/ ui/templates/
  cd ui
  zip -vr ${GITHUB_WORKSPACE}/dist/compress/ui-${RELEASE_TAG}.zip *
  cd ${GITHUB_WORKSPACE}/dist/compress
  #sha256sum ui-${RELEASE_TAG}.zip >> ${GITHUB_WORKSPACE}/dist/compress/sha256.list
  ls -n ${GITHUB_WORKSPACE}/dist/compress
}

RELEASE(){
  cp -r LICENSE README.md ${GITHUB_WORKSPACE}/dist
  cd ${GITHUB_WORKSPACE}/dist
  for f in $(find * -type f -name "${APP_NAME}*"); do
    if [[ "$f" =~ "windows" ]]; then
      zip compress/$(echo $f | sed 's/\.[^.]*$//').zip "$f" LICENSE README.md
    else
      tar -czvf compress/"$f".tar.gz "$f" LICENSE README.md
    fi
    #sha256sum "$f" >> ${GITHUB_WORKSPACE}/dist/compress/sha256.list
  done
}
APP_NAME="$2"
if [ "$1" == 'build' ]; then
  BUILD
  RELEASE
  COMPRESS_UI
elif [ "$1" = "build_musl" ]; then
  BUILD_MUSL
  RELEASE
elif [ "$1" = "release" ]; then
  RELEASE
elif [ "$1" = "docker" ]; then
  BUILD_DOCKER
elif [ "$1" = "nightly_build_docker" ]; then
  NIGHTLY_BUILD_DOCKER
elif [ "$1" == 'nightly_build_ui' ]; then
  NIGHTLY_UI_BUILD
elif [ "$1" == 'nightly_build' ]; then
  BUILD_TARGET="$3"
  NIGHTLY_BUILD
fi