cmake_minimum_required(VERSION 3.14)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.2" CACHE STRING "Minimum OS X deployment version" FORCE)
project(audio_rec LANGUAGES CXX)

#uncomment string below to build with qt
#set(CMAKE_AUTOUIC ON)

#uncomment string below to build with qt
#set(CMAKE_AUTOMOC ON)

#uncomment string below to build with qt
#set(CMAKE_AUTORCC ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

#edit and uncomment string below to build with qt
#set(CMAKE_PREFIX_PATH "~/qt_6.5.2/6.5.2/macos/lib/cmake")

#uncomment string below to build with qt
#find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core)
#uncomment string below to build with qt
#find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core)

find_library(AUDIO_TOOLBOX AudioToolbox)
find_library(CORE_AUDIO CoreAudio)
find_library(CORE_SERVICES CoreServices)
find_library(APPKIT AppKit)
add_executable(audio_rec
    example/main.mm
    api/audiorec.h
    api/audiorec.mm
)

#uncomment string below to build with qt
#target_link_libraries(audio_rec Qt${QT_VERSION_MAJOR}::Core)

target_link_libraries(audio_rec ${AUDIO_TOOLBOX})
target_link_libraries(audio_rec ${CORE_AUDIO})
target_link_libraries(audio_rec ${CORE_SERVICES})
target_link_libraries(audio_rec ${APPKIT})

include(GNUInstallDirs)
install(TARGETS audio_rec
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
