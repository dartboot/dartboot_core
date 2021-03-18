import 'dart:async';

import 'package:dio/dio.dart';

import '../bootstrap/application_context.dart';
import '../error/custom_error.dart';
import '../log/logger.dart';
import '../util/ipaddress.dart';
import '../util/string.dart';
import '../util/uid.dart';
import 'instance.dart';

/// 心跳间隔时间
final Duration defaultHeartbeatDuration = Duration(seconds: 5);

/// 获取应用列表间隔时间
final Duration defaultFetchAppDuration = Duration(seconds: 15);

/// Eureka的客户端
///
/// step1. 注册服务
/// step2. 服务续约
/// step3. 服务下线
/// step4. 获取服务列表、刷新服务列表
class EurekaClient {
  Log logger = Log('EurekaClient');

  static EurekaClient _instance;

  /// APP ID
  final String _appId =
      '${ApplicationContext.instance['app.name'] ?? 'APP_$uid4'}';

  /// 端口号
  final int _port =
      int.parse('${ApplicationContext.instance['server.port'] ?? 8080}');

  /// 实例ID
  String _instanceId;

  /// 心跳的时间调度器
  Timer _heartbeatTimer;

  /// 获取应用列表的时间调度器
  Timer _fetchAppTimer;

  /// DIO客户端
  Dio _rc;

  /// 客户端列表
  List<App> _applications;

  /// 是否准备好
  bool _isReady = false;

  /// 中心地址
  final String defaultZone;

  /// 监听器
  List<StreamController> _appListeners = [];

  static Future<EurekaClient> createSync(defaultZone) async {
    if (null == _instance) {
      _instance = EurekaClient(defaultZone: defaultZone);
      await _instance._register();
      // 监听退出
      ApplicationContext.instance.listenExit(() => _instance._unregister());
    }
    return _instance;
  }

  EurekaClient({this.defaultZone = 'http://localhost:8761/eureka/'}) {
    _initRc();
  }

  static EurekaClient get instance => _instance;

  List<App> get apps => _applications;

  bool get ready => _isReady;

  /// 监听
  void listenApp(StreamController listener) {
    _appListeners.add(listener);
    if (ready) {
      listener.add(DateTime.now());
    }
  }

  /// 初始化Rest客户端
  _initRc() {
    logger.info('Start to initialize rest client...');
    _rc = Dio(BaseOptions(
        receiveDataWhenStatusError: true,
        contentType: 'application/json',
        responseType: ResponseType.json));
    _rc.interceptors
        .add(InterceptorsWrapper(onRequest: (RequestOptions options) async {
      return options; //continue
    }, onResponse: (Response response) async {
      return response; // continue
    }, onError: (DioError e) async {
      logger.error('Eureka client request to center [$defaultZone] failed!', e,
          StackTrace.current);
      return null; //continue
    }));
    logger.info('Rest client initialized.');
  }

  /// 注册客户端
  _register() async {
    _instanceId = '${_appId}:$_port';

    logger.info(
        'Start to register client:[$_instanceId] to center:[$defaultZone]...');

    try {
      var url = '$defaultZone/apps/$_appId';
      var inst = await Instance(
              instanceId: _instanceId,
              ipAddr: await localIp(),
              port: _port,
              appId: _appId,
              contextPath: ApplicationContext.instance['server']['contextPath'],
              status: 'UP')
          .toJson();
      await _rc.post(url, data: {'instance': inst});

      logger.info('Client:[$_instanceId] registered.');

      // 开始获取应用列表
      _startFetchAppTimer();

      // 开启心跳
      _startHeartbeatTimer();
    } catch (e) {
      logger.error('Register failed!', e);
      throw CustomError('无法初始化Eureka客户端');
    }
  }

  /// 开启心跳时间定时器
  _startHeartbeatTimer() {
    if (null != _heartbeatTimer) {
      _heartbeatTimer.cancel();
    }

    // 读取配置
    int hs = ApplicationContext.instance['eureka.heartbeat-interval-seconds'];
    Duration period =
        null != hs ? Duration(seconds: hs) : defaultHeartbeatDuration;
    _heartbeatTimer = Timer.periodic(period, (t) {
      _sendHeartBeat();
    });
  }

  /// 发送心跳
  _sendHeartBeat() async {
    logger.debug('Start to send heartbeat to center:[$defaultZone]...');

    try {
      var url = '$defaultZone/apps/$_appId/$_instanceId?status=UP';
      await _rc.put(url);
    } catch (e) {
      logger.error('Send heartbeat failed!', e);
      throw CustomError('无法发送心跳');
    }

    logger.debug('Send heartbeat success.');
  }

  /// 下线服务
  down() async {
    logger.info('Start to down client...');

    _unregister();

    logger.info('Down client success.');
  }

  /// 上线
  up() async {
    logger.info('Start to up client...');

    _register();

    logger.info('Up client success.');
  }

  /// 关闭
  _shutdown() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _fetchAppTimer?.cancel();
    _fetchAppTimer = null;
  }

  /// 从注册中心移除客户端
  _unregister() async {
    logger.info('Start to unregister client...');

    try {
      _shutdown();
      await _rc.delete('$defaultZone/apps/$_appId/$_instanceId');
    } catch (e) {
      logger.error('Unregister failed!', e);
      throw CustomError('无法移除Eureka客户端');
    }

    logger.info('Unregister client success.');
  }

  /// 开启获取应用列表时间定时器
  _startFetchAppTimer() {
    if (null != _fetchAppTimer) {
      _fetchAppTimer.cancel();
    }
    _fetchApplications();

    // 读取配置
    int fs =
        ApplicationContext.instance['eureka.fetch-registry-interval-seconds'];
    Duration period =
        null != fs ? Duration(seconds: fs) : defaultFetchAppDuration;
    _fetchAppTimer = Timer.periodic(period, (t) {
      _fetchApplications();
    });
  }

  /// 获取应用列表
  _fetchApplications() async {
    logger.debug('Start to fetch applications from center:[$defaultZone]...');

    var url = '$defaultZone/apps/';
    try {
      var res = await _rc.get(url,
          options: Options(headers: {'Accept': 'application/json'}));
      if (!isEmpty(res.data['applications']['application'])) {
        _applications = List.from(res.data['applications']['application'])
            .map((app) => App.fromJson(app))
            .toList();
      }

      // 设置为准备好
      _isReady = true;

      // 通知监听器
      _notifyAppListeners();

      logger.debug('${_applications.length} applications fetched.');

      return true;
    } catch (e) {
      logger.error('Cannot get applications from center.', e);
      return false;
    }
  }

  /// 通知监听器
  _notifyAppListeners() {
    _appListeners
        ?.forEach((cp) => cp.add(DateTime.now().millisecondsSinceEpoch));
  }
}
