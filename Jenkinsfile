pipeline {
  options {
    // 流水线超时设置
    timeout(time:1, unit: 'HOURS')
    //保持构建的最大个数
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  agent {
    label "hk-node"
  }

  environment {
    // 全局环境变量
    // SRC_HARBOR_URL = ""  // 源harbor地址
    // SRC_HARBOR_CRE = credentials('')  // 源harbor用户密码
    // SRC_HARBOR_REGISTRY = "dev"  // 源harbor项目仓库
    DEST_HARBOR_URL = "harbor地址"  // 目标harbor地址
    DEST_HARBOR_CRE = credentials('harbor')  // 目标harbor用户密码
    // DEST_HARBOR_REGISTRY = "library"  // 目标harbor项目仓库, 已使用input
  }  

  parameters {
    // 多行文本输入
    text(name: 'DOCKER_IMAGES', defaultValue: 'nginx:latest', description: '镜像列表, 一行一个')
    choice(name: 'DEST_HARBOR_REGISTRY', choices: 'library', description: '选择同步至仓库项目')
  }

  stages {
    stage('批量同步docker镜像') {
      steps {
        // 写入文件中
        writeFile file: "docker_images.list", text: "$DOCKER_IMAGES\n", encoding: "UTF-8" 
          ansiColor('xterm') {
            echo "#################### 同步镜像开始 ####################"
            sh """set +x
              /bin/bash jenkins_sync_docker_images.sh docker_images.list
            """
            echo "#################### 同步镜像完成 ####################"
          }
      }
    }
  }
}
