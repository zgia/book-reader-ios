# 图书阅读器

纯AI编写，第1个可运行的版本大约花了一个白天的时间。

## AI
`Cursor` + `ChatGPT 5`

## swift
1. 在 `macOS 15.6.1`，`Xcode`，`iPhone 16`模拟器下编译成功
2. 在`iPhone 12 真机`上编译成功

## 数据库SQLite
建库脚本: `BookReader\Resources\book.sql`

### 2025.8.30
目前只读，没有编辑功能。数据库文件`novel.sqlite`必须放在文件App下。
App在真机运行后，会在文件App下创建一个`BookReader`目录，然后连接到手机到电脑，将`novel.sqlite`复制到此目录即可。

开发时，编译代码时，会在控制台输出mac下放置此文件的位置。