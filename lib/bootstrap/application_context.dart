import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:dartboot_annotation/dartboot_annotation.dart';
import 'package:dartboot_util/dartboot_util.dart';
import 'package:yaml/yaml.dart';
import '../error/custom_error.dart';
import '../eureka/eureka.dart';
import '../log/log_system.dart';
import '../log/logger.dart';
import '../server/server.dart';

typedef ExitEvent = Function();

/// DartBoot Application entry side
///
/// 应用的入口类
///
/// @加载配置文件
/// @扫描RestController
/// @启动Http服务
/// @启动Eureka客户端
///
/// @author luodongseu
class ApplicationContext {
  Log logger = Log('DartBootApplication');

  /// 单例
  static ApplicationContext _instance;

  /// 全局的配置
  dynamic _properties = {};

  /// 配置文件路径
  String _configFilePath;

  /// 根目录
  String _rootPath = '.';

  /// 所有的Bean
  List<InstanceMirror> _beans = [];

  /// 所有的控制器
  List<InstanceMirror> _controllers = [];

  /// 启动器，用于注册其他类的启动
  List<Completer> _starters = [];

  /// 系统退出监听器器
  final List<ExitEvent> _exitListeners = [];

  /// 是否正在退出
  bool _exiting = false;

  /// 服务
  Server _server;

  /// 启动参数（如port等）
  List<String> _runArgs = [];

  /// 激活的profile
  String activeProfile = '';

  /// 实例
  static ApplicationContext get instance => _instance;

  String get rootPath => _rootPath;

  List<String> get runArgs => _runArgs;

  ApplicationContext({configFilePath = 'config.yaml',
    String rootPath = '.',
    List<String> runArgs}) {
    _configFilePath = configFilePath;
    _rootPath = rootPath ?? '.';
    _runArgs = runArgs ?? [];
    _instance = this;
  }

  /// 获取全局配置操作
  dynamic operator [](String key) {
    if (key.contains('.')) {
      var _keys = key.split('.');
      dynamic result = _properties;
      for (var i = 0; i < _keys.length; i++) {
        var _r = result[_keys[i]];
        if (null == _r) {
          return null;
        }
        result = _r;
        if (i == _keys.length - 1) {
          return result;
        }
      }
    }
    return _properties[key];
  }

  /// 关闭应用
  void stop() {
    _starters = [];
    _exitListeners.forEach((f) => f());
  }

  /// 初始化操作
  ///
  /// 请在[main.dart]中调用该方法启动DartBoot应用
  void initialize({bool reload = false}) async {
    // 加载配置文件
    _loadProperties(propertiesFilePath: _configFilePath ?? 'config.yaml');

    if (!reload) {
      // 初始化日志系统
      var rootLogLevel = INFO;
      String _rootLogLevel = this['logging.root'];
      switch (_rootLogLevel?.toUpperCase()) {
        case 'DEBUG':
          rootLogLevel = DEBUG;
          break;
        case 'WARNING':
          rootLogLevel = WARNING;
          break;
        case 'ERROR':
          rootLogLevel = ERROR;
          break;
        case 'INFO':
        default:
          rootLogLevel = INFO;
          break;
      }
      LogSystem.init(this['logging.dir'], rootLevel: rootLogLevel);
    }

    // register eureka if need
    if (isNotEmpty(this['eureka'])) {
      await EurekaClient.createSync(this['eureka.zone']);
    }

    // 初始化退出事件监听器
    _listenSystemExit();

    // 扫描带注解的类
    _beans = [];
    _controllers = [];
    await _scanAnnotatedClasses();

    // 开启服务
    await _startServer();

    // 等待所有启动器准备好
    while (!_startersReady) {
      logger.info('Wait starters to ready, try agin 3 secs later...');
      await Future.delayed(Duration(seconds: 3));
    }

    logger.info('Application startup completed.');
  }

  /// 加载配置文件
  void _loadProperties({String propertiesFilePath}) {
    assert(isNotEmpty(propertiesFilePath), '配置文件路径不能为空');

    // 处理特殊参数
    var runArgsMap = _parseRunArgs2Properties();
    print('Run args: $runArgsMap.');

    // 完整路径
    var fullPath = '$_rootPath/resource/$propertiesFilePath';
    print('Config file is: $fullPath.');

    // Bcz log system not initialize
    var file = File(fullPath);
    if (null != file && file.existsSync()) {
      // 读取基本配置文件
      YamlMap yaml = loadYaml(file.readAsStringSync());
      _properties = json.decode(json.encode(yaml)) ?? {};

      String activeProfile = this['profile.active'];
      if (runArgsMap.containsKey('profile.active')) {
        activeProfile = runArgsMap['profile.active'];
      }

      // 读取profile对应的配置文件
      if (isEmpty(_properties['profile'])) {
        _properties['profile'] = {};
      }
      if (isNotEmpty(activeProfile)) {
        var profileFile = File(
            fullPath.replaceFirst(RegExp('.yaml\$'), '-$activeProfile.yaml'));
        if (file.existsSync()) {
          print('Profile config file is: ${profileFile.path}.');
          YamlMap profileYaml = loadYaml(profileFile.readAsStringSync());
          profileYaml.entries.forEach((e) {
            _properties['${e.key}'] = json.decode(json.encode(e.value));
          });
        }
        _properties['profile']['active'] = activeProfile;
      }
      this.activeProfile = _properties['profile']['active'];
    }

    // 覆盖配置
    if (runArgsMap.containsKey('server.port')) {
      if (isEmpty(_properties['server'])) {
        _properties['server'] = {};
      }
      _properties['server']['port'] = runArgsMap['server.port'];
    }
    if (runArgsMap.containsKey('erueka.zone')) {
      if (isEmpty(_properties['erueka'])) {
        _properties['erueka'] = {};
      }
      _properties['erueka']['zone'] = runArgsMap['erueka.zone'];
    }

    // Bcz log system not initialize
//    print('Config properties [$_properties] loaded.');
  }

  /// 处理脚本启动参数
  Map<String, Object> _parseRunArgs2Properties() {
    var argsMap = <String, Object>{};
    // 端口号
    var portArg = runArgs.firstWhere((arg) => '$arg'.startsWith('-Dport='),
        orElse: () => null);
    if (isNotEmpty(portArg)) {
      var port = portArg.replaceFirst('-Dport=', '');
      if (!RegExp(r'^[1-9][0-9]{3,}$').hasMatch(port)) {
        throw CustomError('启动的端口配置错误');
      }
      argsMap['server.port'] = int.parse('${port}');
    }

    // profile
    var profileArg = runArgs.firstWhere(
            (arg) => '$arg'.startsWith('-Dprofile.active='),
        orElse: () => null);
    if (isNotEmpty(profileArg)) {
      var profile = profileArg.replaceFirst('-Dprofile.active=', '');
      if (isEmpty(profile)) {
        throw CustomError('启动的Profile配置错误');
      }
      argsMap['profile.active'] = profile;
    }

    // eureka zone
    var eurekaZoneArg = runArgs.firstWhere(
            (arg) => '$arg'.startsWith('-Derueka.zone='),
        orElse: () => null);
    if (isNotEmpty(eurekaZoneArg)) {
      var eurekaZone = eurekaZoneArg.replaceFirst('-Derueka.zone=', '');
      if (isEmpty(eurekaZone)) {
        throw CustomError('启动的Erueka Zone配置错误');
      }
      argsMap['erueka.zone'] = eurekaZone;
    }

    return argsMap;
  }

  /// 初始化系统进程关闭监听
  void _listenSystemExit() {
    // Ctrl+C handler.
    ProcessSignal.sigint.watch().listen((_) async {
      if (_exiting) {
        return;
      }
      _exiting = true;
      try {
        _exitListeners.forEach((f) => f());
      } catch (e) {
        logger.error('Exit listener invoke failed.', e);
      } finally {
        Future.delayed(Duration(milliseconds: 300), () {
          exit(0);
        });
      }
    });
  }

  /// 扫描带注解的所有dart类
  void _scanAnnotatedClasses() async {
    // 1. Create BuildContext instance which created by build_runner
    // Dynamic import all controller classes
    logger.info('Start to scan annotated classes in application...');
    logger.info('Dynamic class -> [BuildContext] loaded.');

    // 所有的镜像
    _loadAllAnnotatedMirrors();

    logger.info('All annotated classes scanned.');
  }

  /// 加载所有的带有注解的镜子
  ///
  /// 暂时只支持[RestController]、[Bean]注解
  void _loadAllAnnotatedMirrors() {
    var _allBeanInstanceMirrors = <String, InstanceMirror>{};
    var _allControllerInstanceMirrors = <InstanceMirror>[];

    // 是否为合法的对象
    bool isLegalMirror(InstanceMirror m) {
      return m.hasReflectee &&
          (m.reflectee is RestController || m.reflectee is Bean);
    }

    var classMirrors = Queue<ClassMirror>();
    currentMirrorSystem().libraries.values.forEach((lm) {
      lm.declarations.values.forEach((dm) {
        if (dm is ClassMirror && dm.metadata.any((m) => isLegalMirror(m))) {
          classMirrors.add(dm);
        }
      });
    });
    var retry = classMirrors.length;
    var exception = '';
    while (classMirrors.isNotEmpty) {
      var assetMsg = isNotEmpty(exception)
          ? exception
          : 'Retry annotated mirrors failed!';
      if (retry < 0) {
        throw CustomError(assetMsg);
      }

      var dm = classMirrors.removeFirst();
      var isBean = dm.metadata.any((m) => m.reflectee is Bean);
      if (isBean) {
        // bean
        var b = dm.metadata
            .firstWhere((element) => element.reflectee is Bean)
            .reflectee as Bean;
        // 注入条件
        if (isNotEmpty(b.conditionOnProperty) &&
            isEmpty(this[b.conditionOnProperty])) {
          continue;
        }
        // 实例名称
        var beanName = dm.toString();
        if (isNotEmpty(b.name)) {
          beanName = b.name;
        }
        // 依赖检查
        if (isNotEmpty(b.dependencies)) {
          // 检查是否有依赖项未添加
          var hasNotInjectedDep = b.dependencies
              .any((element) => !_allBeanInstanceMirrors.containsKey(element));
          if (hasNotInjectedDep) {
            classMirrors.addLast(dm);
            continue;
          }
        }
        // 实例化
        try {
          _allBeanInstanceMirrors[beanName] = dm.newInstance(Symbol.empty, []);
        } catch (e) {
          exception = e is AssertionError ? e.message : e.toString();
          classMirrors.addLast(dm);
          retry--;
          continue;
        }
      } else {
        // controller
        try {
          _allControllerInstanceMirrors.add(dm.newInstance(Symbol.empty, []));
        } catch (e) {
          classMirrors.addLast(dm);
          retry--;
          continue;
        }
      }
    }

    // 注解类
    _beans.addAll(_allBeanInstanceMirrors.values);
    _handleRestControllers(_allControllerInstanceMirrors);
  }

  /// 加载所有的注解了[RestController]的实例
  void _handleRestControllers(List<InstanceMirror> mirrors) {
    mirrors.forEach((im) {
      var hasAnn = im.type.metadata.any((m) => m.reflectee is RestController);
      if (hasAnn) {
        var rc = im.type.metadata
            .singleWhere((m) => m.reflectee is RestController)
            .reflectee as RestController;
        // 处理RestController基础的路由
        var bp = rc.basePath ?? '/';
        if (!bp.startsWith('/')) {
          bp = '/' + bp;
        }
        _controllers.add(im);
      }
    });
    logger.info(
        'RestController scan finished. Total ${_controllers
            .length} controllers.');
    _controllers.forEach(
            (c) =>
            logger.info('RestController: ${c.type.simpleName} registered.'));
  }

  /// 开启http服务
  void _startServer() async {
    if (null != _server) {
      _server.reload(_controllers);
      return;
    }

    _server = Server(_controllers);
    await _server.start();
  }

  /// 添加启动器，通过[Completer] [Completer.complete()]控制生命周期
  void addStarter(Completer completer) {
    assert(null != completer, 'Parameter must not be null');

    _starters.add(completer);
  }

  /// 添加退出监听器
  void listenExit(ExitEvent event) {
    assert(null != event, 'Parameter must not be null');

    _exitListeners.add(event);
  }

  /// 是否Starters全部准备好
  bool get _startersReady => !_starters.any((c) => !c.isCompleted);
}
