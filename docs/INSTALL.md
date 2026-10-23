# 部署步骤

在 **Kindle Paperwhite 1（2012，固件 5.4.4.2）** 上完整走通过一次。其他 5.x 机型流程基本相同（见 README 的适配表）。

> **动手前先备份。** 把 Kindle 连电脑，把整个 `F:` 盘拷一份出来。整盘大约 500 MB，几分钟的事，但它是你唯一的退路。

---

## 0. 前置

- 一台能连 WiFi 的 Kindle（5.x 固件）
- 数据线、电脑
- 给 Kindle 连好 WiFi（越狱和后续抓数据都要联网）

## 1. 越狱

Kindle 5.x 的越狱是一个**伪装成官方更新的 `.bin` 包**：放到根目录，然后在设置里点"更新您的 Kindle"，它会执行里面的脚本。

1. 下载 K5 越狱包（文件名类似 `kindle-5.4-jailbreak.zip`）：
   <https://kindlemodding.org/jailbreaking/Legacy/K5-Jailbreak/>
2. 解压，**把所有文件**（包括那个名字很怪的 `Update_jb_$(cd mnt && cd us && sh jb.sh).bin`）拷到 Kindle 根目录
3. 弹出设备，Kindle 上进入 **设置 → 菜单（右上角三点）→ 更新您的 Kindle**
4. 屏幕底部出现 `**** JAILBREAK ****` 就是成功了（**没有进度条**，这是正常的，脚本型越狱不刷镜像）
5. 执行完再点一次"更新"会没反应 —— 因为脚本已经把自己删了，这也说明成功

越狱**不会**换掉系统，只是拿到了 root 权限 + 允许运行自定义脚本。

## 2. 放文件

在电脑上准备好这 4 个文件（`build.py` 构建后才有 `index.html`）：

```
/mnt/us/frame/config.sh
/mnt/us/frame/frame.sh
/mnt/us/frame/touchd.sh
/mnt/us/frame/www/index.html
```

拷到 Kindle 的对应位置（`/mnt/us` 就是电脑上看到的 `F:` 根目录）。

## 3. 装开机自启

`S99frame` 是 rc 脚本，开机时把 `frame.sh` 拉起来。

方法一（有 shell 时，最直接）：

```sh
mntroot rw
cp /mnt/us/frame/S99frame /etc/rcS.d/S99frame
chmod +x /etc/rcS.d/S99frame
mntroot ro
```

方法二（**没有 shell，只有越狱包时**）——本项目的做法：

`jb.sh` 执行完后会把根目录的 `*.bin`、`jb.sh` 自己删掉，所以在 `clean_up` **之前**插一行你自己的安装脚本即可：

```sh
# jb.sh 里 print_jb_install_feedback 和 clean_up 之间插一行
sh /mnt/us/payload/install.sh > /mnt/us/payload-log.txt 2>&1
```

`install.sh` 里做方法一那几件事（`mntroot rw` → 拷文件 → `mntroot ro`）。
这样**一次"更新您的 Kindle"就同时完成越狱 + 部署**，不需要先越狱再想办法进去。日志会留在根目录 `payload-log.txt`，插线就能看。

## 4. 去掉地址栏（全屏）

不做这一步，屏幕顶部会一直挂着地址栏、返回键、菜单 —— 一眼就看得出是浏览器。

关键点：**Kindle 的浏览器是 mesquite 框架里的一个 JS 应用**，它的外壳形态由 `config.xml` 决定，把 `viewmodes` 从 `application` 改成 `fullscreen` 就没有地址栏了。

但 **`/var/local/mesquite/browser/config.xml` 每次开机都会被模板重新生成**，所以改 `/var/local` 没用 —— 要改模板：

```sh
mntroot rw
sed -i 's/viewmodes="application"/viewmodes="fullscreen"/' /opt/var/local/mesquite/browser/config.xml
sed -i 's/pinchzoom" value="yes"/pinchzoom" value="no"/'      /opt/var/local/mesquite/browser/config.xml
cp /opt/var/local/mesquite/browser/config.xml /var/local/mesquite/browser/config.xml
mntroot ro
```

> ⚠️ 改之前先备份这个模板：
> `cp /opt/var/local/mesquite/browser/config.xml /mnt/us/frame/opt-config.bak`
>
> 如果改完开机弹出「应用程序出错 / 无法启动选定的应用程序」，就是这个 `viewmodes` 值被固件拒绝了（5.3.x 认，个别 5.4.x 不认），用备份还原即可。

## 5. 重启验证

```sh
reboot
```

开机后大约 **1 分钟**（等系统就绪 + 等 WiFi）自动出现看板。

想确认状态，插线看日志：

```
/mnt/us/frame/frame.log     守护进程日志
/mnt/us/frame/bright.log    触摸 / 背光日志
/mnt/us/frame/upgrade.log   最后一次部署记录
```

正常的话日志里会有：

```
=== frame.sh boot (pid 1737) mounted_after=0x2s ===
system ready after 13x4s (active=[com.lab126.booklet.home])
wifi up after 0x2s
first data built (bat=82 bright=53)
touchd launched
launch try=1 rc=0
browser OK (try=1)
```

## 6. 复原

想退回原来的样子：

- 只想停掉看板：`mntroot rw; rm /etc/rcS.d/S99frame; mntroot ro; reboot`
- 想彻底还原系统文件：用 `opt-config.bak` 还原模板，删掉 `/mnt/us/frame`
- 想回到出厂：把最初那份 `F:` 盘备份拷回去

越狱本身无害（不改系统分区），不想要了把根目录的越狱文件删掉即可。
