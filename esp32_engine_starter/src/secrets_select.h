#pragma once
// secrets.h があればそれを、なければ見本（secrets.example.h）を使う。
#if __has_include("secrets.h")
#include "secrets.h"
#else
#warning "secrets.h がありません。secrets.example.h をコピーして作成してください"
#include "secrets.example.h"
#endif
