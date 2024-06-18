# mirror-images

利用“外网”节点同步镜像至私有 Harbor 仓库

## 使用 Jenkins

## 使用 Github action
请设置 action 环境变量 DEST_HARBOR_URL , secret DEST_HARBOR_CRE_USR 和 DEST_HARBOR_CRE_PSW
通过新建 Issuse 触发

>标题建议为 `[PORTER]镜像名:tag` 的格式，例如`[PORTER]k8s.gcr.io/pause:3.6`    
>issues的内容设定为`skopeo copy`的参数，默认为空

其它参数可以参考：[skopeo copy](https://github.com/containers/skopeo/blob/main/docs/skopeo-copy.1.md)
