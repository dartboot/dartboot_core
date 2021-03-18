library server;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';
import 'package:stack_trace/stack_trace.dart';

import '../annotation/annotation.dart';
import '../bootstrap/application_context.dart';
import '../error/custom_error.dart';
import '../log/logger.dart';
import '../util/string.dart';
import '../util/json.dart';
import '../util/pageable.dart';

part 'request_path.dart';

/// 默认支持的资源文件扩展
const defaultSupportResourceFileExtPatterns = [
  '\.ico',
  '\.html',
  '\.css',
  '\.js',
  '\.jpg',
  '\.jpeg',
  '\.png',
  '\.mp4'
];

/// HttpServer的封装类，用于开启Http[s]服务
///
/// 默认端口启动在8080端口，https开启需要在config中配置
///
/// @author ludongseu
class Server {
  Log logger = Log('HttpServer');

  /// https
  SecurityContext _securityContext;

  /// http服务端口
  int _port = 8080;

  /// http服务
  HttpServer _server;

  /// http服务监听器
  StreamSubscription<HttpRequest> _serverSub;

  /// 动态路径映射
  List<RequestPath> _dynamicPaths = [];

  /// 静态路径（不含路径变量的路由）的map，用于快速索引请求的路由
  Map<String, List<RequestPath>> _staticPathMap = {};

  /// 上下文地址
  String _contextPath;

  /// 支持的资源文件扩展匹配
  List<String> _supportResourceFileExtPatterns = [];

  /// 构造函数
  Server(List<InstanceMirror> controllers) {
    _contextPath = ApplicationContext.instance['server.context-path'] ?? '/';
    _contextPath = '$_contextPath'.replaceAll(RegExp(r'[/]{2,}'), '/');
    _supportResourceFileExtPatterns =
        ApplicationContext.instance['server.static.supportExts'] ??
            defaultSupportResourceFileExtPatterns;
    _initRouter(controllers ?? []);
  }

  /// 重载路由
  close() {
    // cancel
    _serverSub?.cancel();
    _server?.close(force: true);
    _server = null;
  }

  /// 重载
  reload(List<InstanceMirror> controllers) {
    _dynamicPaths = [];
    _staticPathMap = {};
    _initRouter(controllers);
  }

  /// 初始化路由映射
  _initRouter(List<InstanceMirror> controllers) {
    controllers?.forEach((controller) {
      RestController rc = controller.type.metadata
          .firstWhere((m) => m.reflectee is RestController)
          .reflectee as RestController;
      if (null != rc) {
        // 处理RestController基础的路由
        String bp = rc.basePath ?? '/';
        if (!bp.startsWith('/')) {
          bp = '/' + bp;
        }

        // 处理method
        Map<Symbol, MethodMirror> methods = controller.type.instanceMembers;
        methods.forEach((s, m) {
          bool hasHttpMethod = m.metadata.any((mm) =>
              mm.hasReflectee &&
              (mm.reflectee is Get ||
                  mm.reflectee is Post ||
                  mm.reflectee is Delete));
          if (!hasHttpMethod) {
            return;
          }

          Request g = m.metadata
              .firstWhere((_m) => _m.reflectee is Request)
              .reflectee as Request;
          RequestPath requestPath = RequestPath()
            ..method = g.method
            ..basePath = bp
            ..methodMirror = m
            ..responseType = g.responseType
            ..controllerMirror = controller;

          // 原始路径
          String originPath = bp;
          originPath += '/' + g.path;
          originPath = formatUrlPath(originPath);
          if (originPath.length > 1 && originPath.endsWith('/')) {
            originPath = originPath.substring(0, originPath.length - 1);
          }
          requestPath.originPath = originPath;

          // nodes节点
          List<String> sp = originPath.substring(1).split('/');
          bool hasVar = false;
          String regexPath = '';
          List<PathNode> nodes = sp.map((s) {
            PathNode pathNode = PathNode()..text = s;
            if (s.startsWith('{') && s.endsWith('}')) {
              pathNode.isVar = true;
              pathNode.varName = s.substring(1, s.length - 1);
              hasVar = true;
              regexPath += '/[^/]+';
            } else {
              regexPath += '/' + s;
            }
            return pathNode;
          }).toList();
          // 正则表达式，用于快速匹配路由
          requestPath.regexPath = RegExp('\^' + regexPath + '\$');
          requestPath.nodes = nodes;

          if (!hasVar) {
            // 静态路由
            _staticPathMap[originPath] = []
              ..addAll(_staticPathMap[originPath] ?? [])
              ..add(requestPath);
          } else {
            // 动态路由
            _dynamicPaths.add(requestPath);
          }
          logger.info(
              "Bind api:[${requestPath.method?.toString()?.replaceAll('HttpMethod.', '') ?? 'GET'} $originPath] to "
              "controller:[${requestPath.controllerMirror.type.simpleName}]");
        });
      }
    });
  }

  /// 开启服务
  ///
  /// 绑定的端口使用启动配置中的端口，默认为8080
  void start() async {
    logger.info("Start to bind http server to local host...");

    // 配置参数
    dynamic serverConfig = ApplicationContext.instance['server'];
    if (null != serverConfig) {
      if (serverConfig is Map) {
        if (serverConfig.containsKey('port')) {
          _port = int.parse('${serverConfig['port'] ?? _port}');
        }
        if (serverConfig.containsKey('security')) {
          _securityContext = SecurityContext()
            ..useCertificateChain(
                serverConfig['security']['certificateFilePath'])
            ..usePrivateKey(serverConfig['security']['privateKeyFilePath']);
        }
      }
    }

    // 绑定端口并且启动服务监听
    final securityContext = _securityContext;
    try {
      if (securityContext != null) {
        _server = await HttpServer.bindSecure(
            InternetAddress.anyIPv4, _port, securityContext,
            requestClientCertificate: true, v6Only: false, shared: false);
      } else {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, _port,
            v6Only: false, shared: false);
      }
    } catch (e) {
      logger.error('Server started failed.', e, StackTrace.current);
      Future.delayed(Duration(milliseconds: 100), () {
        exit(-1);
      });
      return;
    }

    // // handle errors to response 500 or 404
    _serverSub = _server.listen((request) =>
        runZoned(() => _receiveRequest(request), onError: (e) async {
          logger.error(
              'Request [${request.method} ${request.uri.path}] failed. ${StackTrace.current}',
              e is Error ? e.toString() : e,
              e is Error ? e.stackTrace : null);
          try {
            _sendError(request, CustomError(e.toString()));
          } catch (e) {
            // ignore e
          }
        }, zoneValues: _headerValues(request)));

    // // not handle any error
    // _server.listen((request) => _receiveRequest(request));

    logger.info(
        'Server started on port:$_port and context path:[$_contextPath].');
  }

  /// 处理请求体，
  void _receiveRequest(HttpRequest request) async {
    String reqPath = '${request.uri.path ?? ''}'.trim();
    logger.debug('Request: [${request.method}] $reqPath');

    if (_staticPathMap.isEmpty && _dynamicPaths.isEmpty) {
      _send404(request);
      return;
    }

    // 匹配静态资源文件
    if (matchResource(request)) {
      return;
    }

    // 上下文路径校验
    if (!'$reqPath'.startsWith(_contextPath)) {
      _send404(request);
      return;
    }

    reqPath = reqPath.substring(_contextPath.length);
    if (reqPath != '/') {
      if (!reqPath.startsWith('/')) {
        reqPath = '/' + reqPath;
      }
    }

    // 1. 找静态路径
    if (_staticPathMap.keys.contains(reqPath)) {
      // 找到了全路径匹配
      List<RequestPath> requestPaths = _staticPathMap[reqPath];
      RequestPath backendPath = requestPaths.firstWhere(
          (rp) =>
              '${rp.method}'.replaceAll('HttpMethod.', '').toUpperCase() ==
              request.method,
          orElse: () => null);
      if (null != backendPath) {
        // FIND IT!!
        _handleRequest(backendPath, reqPath, request);
        return;
      }
    }

    // 2. 找动态路径
    int psNum = reqPath.substring(1).split('/').length;
    RequestPath backendPath = _dynamicPaths.firstWhere(
        (rp) =>
            rp.nodes.length == psNum &&
            '${rp.method}'.replaceAll('HttpMethod.', '').toUpperCase() ==
                request.method &&
            rp.regexPath.hasMatch(reqPath),
        orElse: () => null);
    if (null != backendPath) {
      // FIND IT!!
      _handleRequest(backendPath, reqPath, request);
      return;
    }

    // 未找到路由
    _send404(request);
    return;
  }

  /// 处理http请求并响应
  void _handleRequest(
      RequestPath backendPath, String reqPath, HttpRequest request) async {
    logger.debug(
        'Start to handle request: $reqPath with backend: $backendPath...');

    // 分割后的raw path
    List<String> reqPathSplits = [''];
    String lp = reqPath.trim().substring(reqPath.startsWith('/') ? 1 : 0);
    if (lp.length > 0) {
      reqPathSplits = lp.indexOf('/') > 0 ? lp.split('/') : [lp];
    }

    // 路径变量注入值
    Map<String, String> pathVariables = {};
    for (var i = 0; i < reqPathSplits.length; i++) {
      if (backendPath.nodes[i].isVar) {
        pathVariables[backendPath.nodes[i].varName] = reqPathSplits[i];
      }
    }

    // 注入请求头
    Map<String, Object> headers = {};
    request.headers.forEach((k, s) {
      if (s?.isNotEmpty ?? false) {
        headers[k] = s[0];
      }
    });

    // 处理参数
    List<dynamic> params = List();
    for (ParameterMirror p in backendPath.methodMirror.parameters) {
      // HttpRequest
      if (p.type.reflectedType == HttpRequest) {
        params.add(request);
        continue;
      }

      // Path
      var value;
      InstanceMirror pathAnnotation = p.metadata.firstWhere(
          (pm) => pm.hasReflectee && pm.reflectee is Path,
          orElse: () => null);
      if (null != pathAnnotation) {
        final String vn = (pathAnnotation.reflectee as Path).name;
        if (pathVariables.containsKey(vn)) {
          value = pathVariables[vn];
        }
        params.add(convertParameter(value, p));
        continue;
      }

      // Query
      InstanceMirror queryAnnotation = p.metadata.firstWhere(
          (pm) => pm.hasReflectee && pm.reflectee is Query,
          orElse: () => null);
      if (null != queryAnnotation) {
        Query query = queryAnnotation.reflectee as Query;
        final String vn = query.name;
        final bool required = query.required;
        bool queryExists =
            request.uri?.queryParameters?.containsKey(vn) ?? false;
        if (required && !queryExists) {
          _send404(request);
          return;
        }
        value = request.uri?.queryParameters[vn];
        params.add(convertParameter(value, p, query.defaultValue));
        continue;
      }

      // Header
      InstanceMirror headerAnnotation = p.metadata.firstWhere(
          (pm) => pm.hasReflectee && pm.reflectee is Header,
          orElse: () => null);
      if (null != headerAnnotation) {
        final String vn = (headerAnnotation.reflectee as Header).name;
        String header = request.headers.value(vn);
        params.add(convertParameter(header ?? '', p));
        continue;
      }

      // Body
      InstanceMirror bodyAnnotation = p.metadata.firstWhere(
          (pm) => pm.hasReflectee && pm.reflectee is Body,
          orElse: () => null);
      if (null != bodyAnnotation) {
        StringBuffer buffer = await Encoding.getByName('utf-8')
            .decoder
            .bind(request)
            .fold(StringBuffer(), (buffer, data) => buffer..write(data));
        params.add(json.decode(buffer.toString()));
        continue;
      }

      params.add(null);
    }

    // 开始时间
    int start = DateTime.now().millisecondsSinceEpoch;
    logger.debug('Start to invoke api:[$reqPath]\'s controller function...');

    // 指定上下文，将headers加入上下文中
    runZoned(() async {
      Chain.capture(() async {
        // 反射接口函数
        var data = backendPath.controllerMirror
            .invoke(backendPath.methodMirror.simpleName, params)
            .reflectee;
        var result;
        if (data is Future) {
          result = await data;
        } else {
          result = data;
        }
        // 结束时间
        int end = DateTime.now().millisecondsSinceEpoch;
        logger.info(
            'Api:[$reqPath]\'s controller function invoked sucessfuly in [${end - start}] mills.');

        _sendResponse(request, backendPath, result);
      }, onError: (d, e) {
        logger.error(d, e, StackTrace.current);
        if (d is AssertionError) {
          throw CustomError(d.message);
        }
        throw CustomError(d);
      });
    }, zoneValues: headers);
  }

  /// 获取Request的头部消息
  _headerValues(HttpRequest request) {
    var values = {};
    request.headers.forEach((k, v) {
      values[k] = v;
    });
    return values;
  }

  /// 解析参数类型
  dynamic convertParameter(String value, ParameterMirror p,
      [dynamic defaultValue]) {
    String reflectType = p.type?.reflectedType?.toString() ?? 'String';
    switch (reflectType) {
      case 'int':
        return isEmpty(value) ? defaultValue : int.parse(value);
      case 'double':
        return isEmpty(value) ? defaultValue : double.parse(value);
      case 'num':
        return isEmpty(value) ? defaultValue : num.parse(value);
      case 'bool':
        return isEmpty(value)
            ? defaultValue
            : (value == 'true' || value == '1');
      case 'bigint':
        return isEmpty(value) ? defaultValue : BigInt.parse(value);
      case 'List':
        return isEmpty(value) ? defaultValue : value.split(',');
    }
    return isEmpty(value) ? defaultValue : value;
  }

  /// 响应404
  ///
  /// 接口不存在情况下会调用
  void _send404(HttpRequest request) {
    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.add('Content-Type', 'text/html;charset=UTF-8');
    request.response.add('<h1>404</h1><h3>Not found.</h3>'.codeUnits);
    request.response.close();

    logger.error('Resource not found: ${request.uri.path}');
  }

  /// 响应500
  ///
  /// 接口调用失败会响应
  void _sendError(HttpRequest request, CustomError error) {
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.headers.add('Content-Type', 'text/html;charset=UTF-8');
    request.response
        .add(utf8.encode('<h1>500</h1><h3>${error ?? 'Internal error.'}</h3>'));
    request.response.close();

    logger.debug('Response to: ${request.uri.path} error: $error');
  }

  /// 响应200和json格式的内容
  void _sendResponse(
      HttpRequest request, RequestPath requestPath, dynamic data) {
    request.response.statusCode = HttpStatus.ok;
    String contentType;
    dynamic body = '';
    switch (requestPath.responseType) {
      case ResponseType.html:
        contentType = 'text/html';
        body = data;
        break;
      case ResponseType.text:
        contentType = 'text/plain';
        body = data;
        break;
      case ResponseType.json:
      default:
        contentType = 'application/json';
        // 基础类型
        if (data is num || data is bool || data is DateTime) {
          body = '$data';
        } else if (data is String) {
          body = data;
        } else if (null != data) {
          // json
          var _data = data;
          if (_data is PageImpl) {
            _data = _data.toJson();
          }
          body = jsonEncode(_data, toEncodable: encodeJson);
        }
        break;
    }
    request.response.headers
        .add('Content-type', contentType + ';charset=UTF-8');
    request.response.add(utf8.encode(body ?? ''));
    request.response.close();
  }

  /// 匹配favicon
  bool matchResource(HttpRequest request) {
    String path = '${request.uri?.path}';
    if (_supportResourceFileExtPatterns
        .any((p) => RegExp('.*$p').hasMatch(path))) {
      File iconFile = File(formatUrlPath(
          '${ApplicationContext.instance.rootPath}/resource/static/$path'));
      if (iconFile.existsSync()) {
        request.response.headers.contentType = ContentType.binary;
        try {
          request.response.addStream(iconFile.openRead());
        } catch (e) {
          print(e);
          _sendError(request, CustomError('无法读取文件信息'));
        }
      } else {
        _send404(request);
      }
      return true;
    }
    return false;
  }
}
