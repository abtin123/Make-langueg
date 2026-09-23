import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:abtin_maps/routing/routing_engine.dart';

void main() {
  test('routes through canonical map.sqlite views without node_rtree', () async {
    final dir = await Directory.systemTemp.createTemp('abtin-routing-test');
    final dbFile = File('${dir.path}/map.sqlite');
    final db = sqlite3.open(dbFile.path);
    db.execute('CREATE TABLE node_data(id INTEGER PRIMARY KEY, lat_e7 INTEGER, lon_e7 INTEGER)');
    db.execute('CREATE TABLE way_data(way_id INTEGER PRIMARY KEY, class_id INTEGER, name_id INTEGER, access TEXT, junction TEXT, surface TEXT, speed_kmh INTEGER, oneway INTEGER)');
    db.execute('CREATE TABLE categories(id INTEGER PRIMARY KEY, name TEXT)');
    db.execute('CREATE TABLE names(id INTEGER PRIMARY KEY, name TEXT, name_fa TEXT, name_en TEXT)');
    db.execute('CREATE TABLE segments(id INTEGER PRIMARY KEY, a INTEGER, b INTEGER, dist_dm INTEGER, way_id INTEGER)');
    db.execute('CREATE VIRTUAL TABLE road_index USING rtree(id,min_lon,max_lon,min_lat,max_lat,seg_from,seg_to)');
    db.execute('CREATE TABLE turn_restrictions(id INTEGER PRIMARY KEY, restriction TEXT, from_json TEXT, via_json TEXT, to_json TEXT)');
    db.execute('INSERT INTO categories VALUES (1,"primary")');
    db.execute('INSERT INTO names VALUES (1,"Azadi","خیابان آزادی","Azadi")');
    db.execute('INSERT INTO node_data VALUES (10,357000000,514000000),(11,357100000,514100000)');
    db.execute('INSERT INTO way_data VALUES (100,1,1,"","","asphalt",60,1)');
    db.execute('INSERT INTO segments VALUES (1,10,11,14000,100)');
    db.execute('INSERT INTO road_index VALUES (1,51.4000,51.4100,35.7000,35.7100,1,1)');
    db.execute('CREATE VIEW nodes AS SELECT id,lat_e7*1e-7 lat,lon_e7*1e-7 lon FROM node_data');
    db.execute('CREATE VIEW ways AS SELECT w.way_id,c.name road_class,COALESCE(n.name,"") name,COALESCE(w.access,"") access,COALESCE(w.junction,"") junction,COALESCE(w.surface,"") surface FROM way_data w JOIN categories c ON c.id=w.class_id LEFT JOIN names n ON n.id=w.name_id');
    db.execute('CREATE VIEW edges AS SELECT s.id id,s.a start,s.b end,s.dist_dm/10.0 distance_m,w.speed_kmh,w.oneway,s.way_id FROM segments s JOIN way_data w ON w.way_id=s.way_id');
    db.dispose();

    final result = await AbmRoutingEngine().routeDetailed(
      dbFile,
      const RoutePoint(35.7000, 51.4000),
      const RoutePoint(35.7100, 51.4100),
    );

    expect(result, isNotNull);
    expect(result!.points.length, greaterThanOrEqualTo(2));
    expect(result.edges.single.name, 'خیابان آزادی');
    await dir.delete(recursive: true);
  });

test('synthesizes reverse movement for compact two-way segments and snaps inside segments', () async {
  final dir = await Directory.systemTemp.createTemp('abtin-routing-bidir');
  final dbFile = File('${dir.path}/map.sqlite');
  final db = sqlite3.open(dbFile.path);
  db.execute('CREATE TABLE node_data(id INTEGER PRIMARY KEY, lat_e7 INTEGER, lon_e7 INTEGER)');
  db.execute('CREATE TABLE way_data(way_id INTEGER PRIMARY KEY, class_id INTEGER, name_id INTEGER, access TEXT, junction TEXT, surface TEXT, speed_kmh INTEGER, oneway INTEGER)');
  db.execute('CREATE TABLE categories(id INTEGER PRIMARY KEY, name TEXT)');
  db.execute('CREATE TABLE names(id INTEGER PRIMARY KEY, name TEXT, name_fa TEXT, name_en TEXT)');
  db.execute('CREATE TABLE segments(id INTEGER PRIMARY KEY, a INTEGER, b INTEGER, dist_dm INTEGER, way_id INTEGER)');
  db.execute('CREATE VIRTUAL TABLE road_index USING rtree(id,min_lon,max_lon,min_lat,max_lat,seg_from,seg_to)');
  db.execute('CREATE TABLE turn_restrictions(id INTEGER PRIMARY KEY, restriction TEXT, from_json TEXT, via_json TEXT, to_json TEXT)');
  db.execute('INSERT INTO categories VALUES (1,"primary")');
  db.execute('INSERT INTO names VALUES (1,"Test Road","جاده تست","Test Road")');
  db.execute('INSERT INTO node_data VALUES (1,357000000,514000000),(2,357100000,514100000)');
  // Only A -> B is stored. oneway=0 means the app must synthesize B -> A.
  db.execute('INSERT INTO way_data VALUES (10,1,1,"","","asphalt",60,0)');
  db.execute('INSERT INTO segments VALUES (1,1,2,14000,10)');
  db.execute('INSERT INTO road_index VALUES (1,51.4000,51.4100,35.7000,35.7100,1,1)');
  db.execute('CREATE VIEW nodes AS SELECT id,lat_e7*1e-7 lat,lon_e7*1e-7 lon FROM node_data');
  db.execute('CREATE VIEW ways AS SELECT w.way_id,c.name road_class,COALESCE(n.name,"") name,COALESCE(w.access,"") access,COALESCE(w.junction,"") junction,COALESCE(w.surface,"") surface FROM way_data w JOIN categories c ON c.id=w.class_id LEFT JOIN names n ON n.id=w.name_id');
  db.execute('CREATE VIEW edges AS SELECT s.id id,s.a start,s.b end,s.dist_dm/10.0 distance_m,w.speed_kmh,w.oneway,s.way_id FROM segments s JOIN way_data w ON w.way_id=s.way_id');
  db.dispose();

  final result = await AbmRoutingEngine().routeDetailed(
    dbFile,
    const RoutePoint(35.7050, 51.4050),
    const RoutePoint(35.7020, 51.4020),
  );

  expect(result, isNotNull);
  expect(result!.points.length, greaterThanOrEqualTo(2));
  expect(result.edges.single.name, 'جاده تست');
  expect(result.points.first.lat, closeTo(35.7050, 0.00001));
  expect(result.points.last.lat, closeTo(35.7020, 0.00001));
  await dir.delete(recursive: true);
});

}
