# Spring Boot 3.3.8 标准 Java 17 后端规范

**版本声明模板** - 本文档定义标准 Spring Boot 3.3.8 + JDK 17 后端项目的依赖版本、构建配置和质量验证规范。

**适用范围:** 所有基于 Spring Boot 3.3.8 的 Java 17 后端项目

---

## 快速索引

| 章节 | 内容 |
|------|------|
| [依赖版本清单](#依赖版本清单) | 核心依赖、内置组件、构建插件 |
| [项目配置模板](#项目配置模板) | pom.xml 通用配置 |
| [质量验证规范](#质量验证规范) | 验证依赖与命令（wf-dev 验证类技能） |

---

## 依赖版本清单

### 核心依赖规范

| 依赖类型 | GroupId | ArtifactId | 版本 | 作用域 | 必选 |
|----------|---------|-----------|------|--------|------|
| **Parent POM** | org.springframework.boot | spring-boot-starter-parent | 3.3.8 | parent | ✅ |
| **Web 框架** | org.springframework.boot | spring-boot-starter-web | parent 管理 | compile | ✅ |
| **安全框架** | org.springframework.boot | spring-boot-starter-security | parent 管理 | compile | ✅ |
| **数据验证** | org.springframework.boot | spring-boot-starter-validation | parent 管理 | compile | ✅ |
| **缓存** | org.springframework.boot | spring-boot-starter-data-redis | parent 管理 | compile | ⚪ |
| **数据访问** | org.springframework.boot | spring-boot-starter-data-jpa | parent 管理 | compile | ⚪ |
| **测试** | org.springframework.boot | spring-boot-starter-test | parent 管理 | test | ✅ |
| **JWT 核心** | io.jsonwebtoken | jjwt-api | 0.12.6 | compile | ⚪ |
| **JWT 实现** | io.jsonwebtoken | jjwt-impl | 0.12.6 | runtime | ⚪ |
| **JWT 序列化** | io.jsonwebtoken | jjwt-jackson | 0.12.6 | runtime | ⚪ |
| **MySQL 驱动** | com.mysql | mysql-connector-j | parent 管理 | runtime | ⚪ |
| **测试数据库** | com.h2database | h2 | parent 管理 | test | ✅ |
| **验证码** | com.github.penggle | kaptcha | 2.3.2 | compile | ⚪ |

**图例:** ✅ 必选 | ⚪ 可选

**标准 properties:**
```xml
<properties>
    <java.version>17</java.version>
    <jjwt.version>0.12.6</jjwt.version>
</properties>
```

### Spring Boot 3.3.8 内置组件版本

以下组件由 Spring Boot Parent 管理，无需显式声明版本：

| 组件 | 版本 | 说明 |
|------|------|------|
| Spring Framework | 6.1.16 | 核心框架 |
| Spring Security | 6.3.6 | 安全框架 |
| Tomcat | 10.1.34 | 内嵌容器 |
| Jackson | 2.17.3 | JSON 序列化 |
| Hibernate | 6.5.3.Final | ORM 框架 |
| Hibernate Validator | 8.0.2.Final | Bean 验证 |
| Logback | 1.5.14 | 日志实现 |
| SLF4J | 2.0.16 | 日志门面 |
| HikariCP | 5.1.0 | 连接池 |

### 构建插件规范

| 插件 | 版本 | 用途 | 执行阶段 |
|------|------|------|-----------|
| **代码检查** ||||
| maven-checkstyle-plugin | 3.3.1 | 代码风格检查 | 验证 |
| spotbugs-maven-plugin | 4.8.3.0 | 静态缺陷扫描 | 验证 |
| maven-pmd-plugin | 3.21.2 | 代码规范扫描 | 验证 |
| **安全审计** ||||
| dependency-check-maven | 9.0.9 | CVE 漏洞扫描 | 验证 |
| **质量保证** ||||
| jacoco-maven-plugin | 0.8.11 | 测试覆盖率 | 验证 |
| spotless-maven-plugin | 2.43.0 | 代码格式化 | 修复 |
| **构建打包** ||||
| spring-boot-maven-plugin | 3.3.8 | 可执行 jar 打包 | package |

---

## 项目配置模板

### pom.xml 模板

**用途:** 新项目初始化时的 pom.xml 基础配置

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <!-- === Parent POM === -->
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.3.8</version>
        <relativePath/>
    </parent>

    <!-- === 项目信息（需自定义） === -->
    <groupId>com.yourcompany</groupId>  <!-- 替换为实际 groupId -->
    <artifactId>your-service-name</artifactId>  <!-- 替换为实际 artifactId -->
    <version>1.0.0</version>
    <name>Your Service Name</name>  <!-- 替换为实际项目名称 -->
    <description>Service description</description>

    <!-- === 通用配置 === -->
    <properties>
        <java.version>17</java.version>
        <jjwt.version>0.12.6</jjwt.version>
        <!-- 项目特定的属性可在此添加 -->
    </properties>

    <!-- === 依赖管理 === -->
    <dependencies>
        <!-- Spring Boot Starters（按需选择） -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>

        <!-- 可选依赖（按需取消注释） -->
        <!--
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>

        <dependency>
            <groupId>com.mysql</groupId>
            <artifactId>mysql-connector-j</artifactId>
            <scope>runtime</scope>
        </dependency>

        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-api</artifactId>
            <version>${jjwt.version}</version>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-impl</artifactId>
            <version>${jjwt.version}</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-jackson</artifactId>
            <version>${jjwt.version}</version>
            <scope>runtime</scope>
        </dependency>

        <dependency>
            <groupId>com.github.penggle</groupId>
            <artifactId>kaptcha</artifactId>
            <version>2.3.2</version>
        </dependency>
        -->

        <!-- 测试依赖 -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>com.h2database</groupId>
            <artifactId>h2</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <!-- === 构建插件 === -->
    <build>
        <plugins>
            <!-- Spring Boot 打包插件 -->
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>

            <!-- Lint & 静态分析 -->
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

            <!-- 安全审计 -->
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

            <!-- 测试覆盖率 -->
            <plugin>
                <groupId>org.jacoco</groupId>
                <artifactId>jacoco-maven-plugin</artifactId>
                <version>0.8.11</version>
                <configuration>
                    <rules>
                        <rule>
                            <element>BUNDLE</element>
                            <limits>
                                <limit>
                                    <counter>LINE</counter>
                                    <value>COVEREDRATIO</value>
                                    <minimum>0.70</minimum>
                                </limit>
                            </limits>
                        </rule>
                    </rules>
                </configuration>
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
                    <execution>
                        <id>check</id>
                        <phase>verify</phase>
                        <goals><goal>check</goal></goals>
                    </execution>
                </executions>
            </plugin>

            <!-- 代码格式化 -->
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
        </plugins>
    </build>
</project>
```

### 标准项目目录结构

```
{项目根目录}/
├── pom.xml
├── .gitignore
└── src/
    ├── main/
    │   ├── java/{package}/
    │   │   ├── {Application}.java           # Spring Boot 启动类
    │   │   ├── config/                     # 配置类
    │   │   ├── controller/                 # REST 控制器
    │   │   ├── dto/
    │   │   │   ├── request/                # 请求 DTO
    │   │   │   └── response/               # 响应 DTO
    │   │   ├── exception/                  # 异常定义和处理
    │   │   ├── filter/                     # 过滤器
    │   │   ├── repository/                 # 数据访问层
    │   │   ├── service/                    # 业务逻辑接口
    │   │   │   └── impl/                   # 业务逻辑实现
    │   │   └── util/                       # 工具类
    │   └── resources/
    │       ├── application.yml             # 主配置文件
    │       ├── application-dev.yml         # 开发环境配置
    │       └── application-test.yml        # 测试环境配置
    └── test/
        └── java/{package}/                 # 测试代码
            ├── controller/
            ├── service/
            └── repository/
```

---

## 质量验证规范

### 系统级依赖

| 工具 | 版本要求 | 用途 | 验证命令 |
|------|----------|------|----------|
| Maven | 3.9.x | 构建管理 | `mvn -v` |
| Java | 17+ | 运行环境 | `java -version` |
| Redis | 任意版本 | 缓存依赖（可选） | `redis-cli ping` |

### 质量验证（wf-dev 验证类技能）

#### 依赖版本一致性检查（推荐）

检查项目依赖版本是否与本规范一致，如一致可跳过部分重量级检查。（如项目配置有版本比对脚本，则执行脚本并输出对比报告；否则人工核对 `pom.xml` 与本文件版本清单）

**跳过条件:** 依赖版本一致 → 可跳过 lint/安全审计/测试验证

#### Lint 与静态分析

**Checkstyle:**
```bash
mvn checkstyle:check
```

**SpotBugs:**
```bash
mvn spotbugs:check
```

**PMD:**
```bash
mvn pmd:check
```

**并行执行:**
```bash
mvn checkstyle:check spotbugs:check pmd:check
```

#### 安全审计

**Dependency Check:**
```bash
mvn org.owasp:dependency-check-maven:check
```

**说明:** 首次运行下载 NVD 数据库需 5-10 分钟。CVSS ≥ 7 触发失败。

#### 测试验证

**完整测试 + 覆盖率:**
```bash
mvn clean test jacoco:report
```

**仅测试:**
```bash
mvn test
```

**目标覆盖率:** 以 `.qoder/wf-dev.yaml` `coverage.*` 为准（默认 `new_code: 100` / `overall: 70`）

### 自动修复

#### 代码格式化

**检查格式:**
```bash
mvn spotless:check
```

**自动修复:**
```bash
mvn spotless:apply
```

### CICD 验证

#### 构建验证

```bash
mvn clean package -DskipTests
```

#### 集成测试

```bash
mvn spring-boot:run
# 另起终端: curl http://localhost:8080/api/health
```

#### 数据库验证

本项目推荐使用 schema auto-init 模式（`CREATE TABLE IF NOT EXISTS`），通过启动日志验证表创建成功。

**可选 Flyway:**
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

---

## 版本维护

### 更新原则

1. **单一真实来源** - 本文件是版本定义的唯一来源
2. **向后兼容** - 主版本更新需评估影响
3. **测试验证** - 更新后需验证兼容性

### 禁止操作

- ❌ 禁止使用 Spring Boot Parent 不支持的非规范版本
- ❌ 禁止跳过版本验证直接使用最新版
- ❌ 禁止在其他地方硬编码本文件定义的版本

### 相关模板

- **前端版本模板:** `front-rules/rules-vue-lite/frontend-versions-template.md`（路径以 `.qoder/wf-rules/tech-stacks/` 为基准）