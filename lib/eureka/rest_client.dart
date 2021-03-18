import 'dart:async';

import 'package:dio/dio.dart';

import '../error/custom_error.dart';
import '../log/logger.dart';
import '../util/string.dart';
import 'client.dart';
import 'instance.dart';
import 'load_balancer.dart';
import 'runner.dart';

/// Eureka的REST接口客户端
///
/// 用于调用微服务（带负载均衡）的工具
///
/// @author luodongseu
class EurekaRestClient {
  Log logger = Log('EurekaRestClient');

  /// 服务的ID
  final String serviceId;

  /// 根路径
  final String rootPath;

  /// APP信息
  App _app;

  /// 远程地址列表
  List<String> _remoteAddresses = [];

  /// 负载均衡器
  LoadBalancer _loadBalancer;

  /// 客户端
  Dio _rc;

  /// APP信息监听器
  StreamController _appListener = StreamController.broadcast();

  EurekaRestClient(this.serviceId, {this.rootPath = '/'}) {
    _rc = Dio(BaseOptions(connectTimeout: 30000));

    _initListener();
  }

  /// 初始化监听器
  _initListener() async {
    // 监听启动
    _appListener.stream.listen((data) {
      loadAppAndLoadBalancerIfNeed(force: true);
    });

    // 等待EurekaClient初始化完成
    while (null == EurekaClient.instance) {
      await Future.delayed(Duration(milliseconds: 100));
    }
    EurekaClient.instance.listenApp(_appListener);
  }

  /// Handy method to make http GET request, which is a alias of  [BaseDio.request].
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic> queryParameters,
    Options options,
    CancelToken cancelToken,
    ProgressCallback onReceiveProgress,
  }) async {
    if (!loadAppAndLoadBalancerIfNeed())
      throw CustomError('未找到对应的服务[id=$serviceId]');
    return _loadBalancer?.run(
      path,
      queryParameters: queryParameters,
      options: checkOptions('GET', options),
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }

  /// Handy method to make http POST request, which is a alias of  [BaseDio.request].
  Future<Response<T>> post<T>(
    String path, {
    data,
    Map<String, dynamic> queryParameters,
    Options options,
    CancelToken cancelToken,
    ProgressCallback onSendProgress,
    ProgressCallback onReceiveProgress,
  }) async {
    if (!loadAppAndLoadBalancerIfNeed())
      throw CustomError('未找到对应的服务[id=$serviceId]');
    return _loadBalancer?.run(
      path,
      data: data,
      queryParameters: queryParameters,
      options: checkOptions('POST', options),
      onReceiveProgress: onReceiveProgress,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// Handy method to make http PUT request, which is a alias of  [BaseDio.request].
  Future<Response<T>> put<T>(
    String path, {
    data,
    Map<String, dynamic> queryParameters,
    Options options,
    CancelToken cancelToken,
    ProgressCallback onSendProgress,
    ProgressCallback onReceiveProgress,
  }) async {
    if (!loadAppAndLoadBalancerIfNeed())
      throw CustomError('未找到对应的服务[id=$serviceId]');
    return _loadBalancer?.run(
      path,
      data: data,
      queryParameters: queryParameters,
      options: checkOptions('PUT', options),
      onReceiveProgress: onReceiveProgress,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// Handy method to make http HEAD request, which is a alias of [BaseDio.request].
  Future<Response<T>> head<T>(
    String path, {
    data,
    Map<String, dynamic> queryParameters,
    Options options,
    CancelToken cancelToken,
  }) async {
    if (!loadAppAndLoadBalancerIfNeed())
      throw CustomError('未找到对应的服务[id=$serviceId]');
    return _loadBalancer?.run(
      path,
      data: data,
      queryParameters: queryParameters,
      options: checkOptions('HEAD', options),
      cancelToken: cancelToken,
    );
  }

  /// Handy method to make http DELETE request, which is a alias of  [BaseDio.request].
  Future<Response<T>> delete<T>(
    String path, {
    data,
    Map<String, dynamic> queryParameters,
    Options options,
    CancelToken cancelToken,
  }) async {
    if (!loadAppAndLoadBalancerIfNeed())
      throw CustomError('未找到对应的服务[id=$serviceId]');
    return _loadBalancer?.run(
      path,
      data: data,
      queryParameters: queryParameters,
      options: checkOptions('DELETE', options),
      cancelToken: cancelToken,
    );
  }

  /// Handy method to make http PATCH request, which is a alias of  [BaseDio.request].
  Future<Response<T>> patch<T>(
    String path, {
    data,
    Map<String, dynamic> queryParameters,
    Options options,
    CancelToken cancelToken,
    ProgressCallback onSendProgress,
    ProgressCallback onReceiveProgress,
  }) async {
    if (!loadAppAndLoadBalancerIfNeed())
      throw CustomError('未找到对应的服务[id=$serviceId]');
    return _loadBalancer?.run(
      path,
      data: data,
      queryParameters: queryParameters,
      options: checkOptions('PATCH', options),
      onReceiveProgress: onReceiveProgress,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// 加载APP信息和负载均衡客户端
  bool loadAppAndLoadBalancerIfNeed({bool force = false}) {
    if (!force && null != _app) {
      return true;
    }
    if (null == EurekaClient.instance) {
      logger.warning('正在初始化...');
      return false;
    }
    if (!EurekaClient.instance.ready) {
      logger.warning('正在加载服务列表...');
      return false;
    }

    logger.debug(
        'Start to refresh app:[id=$serviceId]\'s instance list and load balancer...');

    App app = EurekaClient.instance.apps.firstWhere((a) {
      return a.name?.toUpperCase() == serviceId.toUpperCase();
    }, orElse: () => null);
    if (null == app) {
      logger.warning('未找到目标服务[id=$serviceId]...');
      return false;
    }

    // 过滤关闭的实例
    List<Instance> _allInstances = []..addAll(app.instance);
    _allInstances.retainWhere((ins) => ins.status == 'UP');
    if (isEmpty(_allInstances)) {
      logger.warning('未找到目标服务[id=$serviceId]的可用实例...');
      return false;
    }
    _app = app;

    // 刷新实例负载均衡器
    List<String> remoteHostAndPorts = [];
    for (int i = 0; i < _allInstances.length; i++) {
      remoteHostAndPorts
          .add('${_allInstances[i].ipAddr}:${_allInstances[i].port}');
    }
    if (_remoteAddresses.length != _allInstances.length ||
        _remoteAddresses.any((add) => !remoteHostAndPorts.contains(add))) {
      List<Runner> runners = [];
      remoteHostAndPorts.forEach(
          (ra) => runners.add(EurekaRestClientRunner(ra, rootPath, _rc)));
      _loadBalancer?.close();
      _loadBalancer = LoadBalancer(runners);
    }

    logger.debug(
        'App:[id=$serviceId] loaded with ${remoteHostAndPorts.length} instances: $remoteHostAndPorts]');

    return true;
  }

  Options checkOptions(method, options) {
    options ??= Options();
    options.method = method;
    return options;
  }
}

/// Runner实例
class EurekaRestClientRunner extends Runner {
  Log logger = Log('EurekaRestClientRunner');

  /// 远端路径，直接返回
  final String remoteAddress;

  /// 根路径
  final String rootPath;

  /// DIO客户端
  final Dio client;

  EurekaRestClientRunner(this.remoteAddress, this.rootPath, this.client);

  /// 合并请求路径
  Future<String> combinePath(String path) async {
    String _p = remoteAddress + '/' + rootPath + '/' + path;
    return 'http://' + _p.replaceAll(RegExp('[/]{2,}'), '/');
  }

  @override
  Future<Response<R>> run<R>(String path,
      {data,
      Map<String, dynamic> queryParameters,
      CancelToken cancelToken,
      Options options,
      ProgressCallback onSendProgress,
      ProgressCallback onReceiveProgress}) async {
    String p = await combinePath(path);
    logger.debug(
        'Start to invoke eureka rest client with url: [${options?.method} $p]...');
    return client.request(
      p,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }
}
