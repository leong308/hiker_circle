package com.leongziqi.hikercircle

import androidx.core.content.FileProvider

/** Separate provider identity avoids merging with camera/gallery providers. */
class HikeShareFileProvider : FileProvider()
