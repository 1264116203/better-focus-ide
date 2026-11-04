# Java 后端验证依赖项与安装方法

本文件列出 wf-dev 工作流后端验证环节（ss-tdd-cycle 测试生成 / ss-test-run 测试执行 / ss-test-integration 真实联调）所需的依赖项，以及 Spring Boot 3.x + Java 17 项目中的安装方法。

## 一、系统级依赖

| 工具 | 用途 | 安装/确认方式 |
|------|------|---------------|
| Maven 3.9+ | 构建测试全流程 | `mvn -v` 确认 |
| Java 17 | 编译运行 | `java -version` 确认 |
| Redis | 集成测试缓存（如项目使用） | `redis-cli ping` → PONG |
| mysql-client | 数据库连接验证（如项目使用） | `brew install mysql-client` |

## 二、pom.xml Maven 插件（按需在 `<build><plugins>` 中声明）

以下插件按项目需要声明，缺失时安装对应依赖。

### 1. 代码风格与静态分析

#### maven-checkstyle-plugin — 代码风格检查

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-checkstyle-plugin</artifactId>
    <version>3.3.1</version>
    <dependencies>
        <dependency>
            <groupId>com.puppycrawl.tools</groupId>
            <artifactId>checkstyle</artifactId>
            <version>10.12.4</version>
        </dependency>
    </dependencies>
    <configuration>
        <configLocation>google_checks.xml</configLocation>
        <encoding>UTF-8</encoding>
        <consoleOutput>true</consoleOutput>
        <failsOnError>true</failsOnError>
    </configuration>
    <executions>
        <execution>
            <id>validate</id>
            <phase>validate</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

执行命令: `mvn checkstyle:check`

#### spotbugs-maven-plugin — 静态缺陷扫描

```xml
<plugin>
    <groupId>com.github.spotbugs</groupId>
    <artifactId>spotbugs-maven-plugin</artifactId>
    <version>4.8.3.0</version>
    <dependencies>
        <dependency>
            <groupId>com.github.spotbugs</groupId>
            <artifactId>spotbugs</artifactId>
            <version>4.8.3</version>
        </dependency>
    </dependencies>
    <configuration>
        <effort>Max</effort>
        <threshold>Low</threshold>
        <failOnError>true</failOnError>
    </configuration>
    <executions>
        <execution>
            <id>spotbugs-check</id>
            <phase>verify</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

执行命令: `mvn spotbugs:check`

#### maven-pmd-plugin — 代码规范扫描

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-pmd-plugin</artifactId>
    <version>3.21.2</version>
    <dependencies>
        <dependency>
            <groupId>net.sourceforge.pmd</groupId>
            <artifactId>pmd-core</artifactId>
            <version>6.55.0</version>
        </dependency>
        <dependency>
            <groupId>net.sourceforge.pmd</groupId>
            <artifactId>pmd-java</artifactId>
            <version>6.55.0</version>
        </dependency>
    </dependencies>
    <configuration>
        <rulesets>
            <ruleset>category/java/errorprone.xml</ruleset>
            <ruleset>category/java/security.xml</ruleset>
            <ruleset>category/java/bestpractices.xml</ruleset>
        </rulesets>
        <failOnViolation>true</failOnViolation>
    </configuration>
    <executions>
        <execution>
            <id>pmd-check</id>
            <phase>verify</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

执行命令: `mvn pmd:check`

### 2. 安全审计

#### dependency-check-maven — CVE 依赖漏洞扫描

```xml
<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>9.0.9</version>
    <configuration>
        <failBuildOnCVSS>7</failBuildOnCVSS>
        <suppressionFile>dependency-check-suppression.xml</suppressionFile>
    </configuration>
    <executions>
        <execution>
            <id>dependency-check</id>
            <phase>verify</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

执行命令: `mvn org.owasp:dependency-check-maven:check`

**注意:** 首次运行会下载 NVD 数据库，耗时较长（约 5-10 分钟）。CVSS ≥ 7 触发构建失败（安全零容忍）。

### 3. 测试覆盖率

#### jacoco-maven-plugin — 测试覆盖率

```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <version>0.8.11</version>
    <executions>
        <execution>
            <id>prepare-agent</id>
            <goals><goal>prepare-agent</goal></goals>
        </execution>
        <execution>
            <id>report</id>
            <phase>test</phase>
            <goals><goal>report</goal></goals>
        </execution>
    </executions>
</plugin>
```

执行命令: `mvn clean test jacoco:report`

覆盖率报告输出路径: `target/site/jacoco/index.html`

> 覆盖率阈值**不在 pom.xml 中硬编码**，以 `.qoder/wf-dev.yaml` 的 `coverage.*` 配置为准（默认 `new_code: 100` / `overall: 70`），执行验证时读取校验。

### 4. 自动格式化

#### spotless-maven-plugin — 代码自动格式化

```xml
<plugin>
    <groupId>com.diffplug.spotless</groupId>
    <artifactId>spotless-maven-plugin</artifactId>
    <version>2.43.0</version>
    <configuration>
        <java>
            <googleJavaFormat>
                <version>1.17.0</version>
                <style>AOSP</style>
            </googleJavaFormat>
            <removeUnusedImports/>
            <trimTrailingWhitespace/>
            <endWithNewline/>
        </java>
    </configuration>
    <executions>
        <execution>
            <id>spotless-check</id>
            <phase>verify</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

执行命令:
- 检查: `mvn spotless:check`
- 自动修复: `mvn spotless:apply`

### 5. 数据库迁移（按项目既有模式）

遵循项目现有迁移模式验证（schema auto-init / 启动脚本 / Flyway 等），启动服务验证初始化逻辑正确执行：

```bash
# 启动服务，验证 schema 初始化
mvn spring-boot:run

# 通过日志确认表创建成功（日志含 "Created table" 或 "Table already exists"）
# 通过 API 测试确认 CRUD 正常
```

**如需 Flyway（可选添加）:**

```xml
<plugin>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-maven-plugin</artifactId>
    <version>10.4.1</version>
    <configuration>
        <url>${spring.datasource.url}</url>
        <user>${spring.datasource.username}</user>
        <password>${spring.datasource.password}</password>
    </configuration>
</plugin>
```

## 三、测试依赖（通常已有）

| 依赖 | 来源 | 用途 |
|------|------|------|
| spring-boot-starter-test | pom.xml（Spring Boot 默认） | 含 JUnit 5、Mockito、AssertJ、Spring Test |
| h2 | pom.xml（Spring Boot 默认） | 单元测试内存数据库 |

## 四、wf-dev 技能对应命令速查

| 技能 | 检查项 | 命令 |
|------|--------|------|
| ss-tdd-cycle | 单元测试（红绿循环） | `mvn -q test` |
| ss-test-run | 测试执行与报告 | `mvn -q test` / `mvn -q verify` |
| ss-test-integration | 真实环境联调 | `mvn spring-boot:run` + curl API 验证 |
| 安全门禁 | 依赖审计 | `mvn org.owasp:dependency-check-maven:check` |

**全栈项目注意：** 前端验证并行执行，命令见 `wf-rules/tech-stacks/front-rules/` 对应栈规则。所有验证结论必须附真实命令输出证据（证据先于宣称），任一 FAIL 即整体 FAIL，禁止宣称完成。
