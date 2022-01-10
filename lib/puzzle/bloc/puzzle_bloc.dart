// ignore_for_file: public_member_api_docs

import 'dart:math';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:very_good_slide_puzzle/models/models.dart';

part 'puzzle_event.dart';
part 'puzzle_state.dart';

const _url =
    'https://cdn.pixabay.com/photo/2015/04/23/22/00/tree-736885__480.jpg';

class PuzzleBloc extends Bloc<PuzzleEvent, PuzzleState> {
  PuzzleBloc(this._size, {this.random, this.url = _url})
      : super(const PuzzleState()) {
    on<PuzzleInitialized>(_onPuzzleInitialized);
    on<TileTapped>(_onTileTapped);
    on<PuzzleReset>(_onPuzzleReset);
  }

  final int _size;

  final Random? random;

  final String url;

  Future<void> _onPuzzleInitialized(
    PuzzleInitialized event,
    Emitter<PuzzleState> emit,
  ) async {
    final puzzle = await _generatePuzzle(_size, shuffle: event.shufflePuzzle);
    emit(
      PuzzleState(
        puzzle: puzzle.sort(),
        numberOfCorrectTiles: puzzle.getNumberOfCorrectTiles(),
      ),
    );
  }

  void _onTileTapped(TileTapped event, Emitter<PuzzleState> emit) {
    final tappedTile = event.tile;
    if (state.puzzleStatus == PuzzleStatus.incomplete) {
      if (state.puzzle.isTileMovable(tappedTile)) {
        final mutablePuzzle = Puzzle(tiles: [...state.puzzle.tiles]);
        final puzzle = mutablePuzzle.moveTiles(tappedTile, []);
        if (puzzle.isComplete()) {
          emit(
            state.copyWith(
              puzzle: puzzle.sort(),
              puzzleStatus: PuzzleStatus.complete,
              tileMovementStatus: TileMovementStatus.moved,
              numberOfCorrectTiles: puzzle.getNumberOfCorrectTiles(),
              numberOfMoves: state.numberOfMoves + 1,
              lastTappedTile: tappedTile,
            ),
          );
        } else {
          emit(
            state.copyWith(
              puzzle: puzzle.sort(),
              tileMovementStatus: TileMovementStatus.moved,
              numberOfCorrectTiles: puzzle.getNumberOfCorrectTiles(),
              numberOfMoves: state.numberOfMoves + 1,
              lastTappedTile: tappedTile,
            ),
          );
        }
      } else {
        emit(
          state.copyWith(tileMovementStatus: TileMovementStatus.cannotBeMoved),
        );
      }
    } else {
      emit(
        state.copyWith(tileMovementStatus: TileMovementStatus.cannotBeMoved),
      );
    }
  }

  Future<void> _onPuzzleReset(
      PuzzleReset event, Emitter<PuzzleState> emit) async {
    final puzzle = await _generatePuzzle(_size);
    emit(
      PuzzleState(
        puzzle: puzzle.sort(),
        numberOfCorrectTiles: puzzle.getNumberOfCorrectTiles(),
      ),
    );
  }

  /// Build a randomized, solvable puzzle of the given size.
  Future<Puzzle> _generatePuzzle(int size, {bool shuffle = true}) async {
    final correctPositions = <Position>[];
    final currentPositions = <Position>[];
    final scatterBytes = <Uint8List>[];

    final whitespacePosition = Position(x: size, y: size);

    final bytes = (await NetworkAssetBundle(Uri.parse(url)).load(url))
        .buffer
        .asUint8List();
    final defaultImage = img.decodeImage(bytes)!;
    final croppedImage = img.copyResizeCropSquare(defaultImage, 500);

    var a = 0, b = 0;
    final width = (croppedImage.width / size).round();
    final height = (croppedImage.height / size).round();

    // Create all possible board positions.
    for (var y = 1; y <= size; y++) {
      for (var x = 1; x <= size; x++) {
        final image = img.copyCrop(croppedImage, a, b, width, height);
        scatterBytes.add(Uint8List.fromList(img.encodeJpg(image)));
        if (x == size && y == size) {
          correctPositions.add(whitespacePosition);
          currentPositions.add(whitespacePosition);
        } else {
          final position = Position(x: x, y: y);
          correctPositions.add(position);
          currentPositions.add(position);
        }
        a += width;
      }
      a = 0;
      b += height;
    }

    if (shuffle) {
      // Randomize only the current tile posistions.
      currentPositions.shuffle(random);
    }

    var tiles = _getTileListFromPositions(
      size,
      scatterBytes,
      correctPositions,
      currentPositions,
    );

    var puzzle = Puzzle(tiles: tiles);

    if (shuffle) {
      // Assign the tiles new current positions until the puzzle is solvable and
      // zero tiles are in their correct position.
      while (!puzzle.isSolvable() || puzzle.getNumberOfCorrectTiles() != 0) {
        currentPositions.shuffle(random);
        tiles = _getTileListFromPositions(
          size,
          scatterBytes,
          correctPositions,
          currentPositions,
        );
        puzzle = Puzzle(tiles: tiles);
      }
    }

    return puzzle;
  }

  /// {@template split_image}
  Future<List<Uint8List>> splitImage(String url, int size, int count) async {
    final bytes = (await NetworkAssetBundle(Uri.parse(url)).load(url))
        .buffer
        .asUint8List();
    // convert image to image from image package
    final defaultImage = img.decodeImage(bytes)!;
    final image = img.copyResizeCropSquare(defaultImage, size);

    var x = 0, y = 0;
    final width = (image.width / count).round();
    final height = (image.height / count).round();

    // split image to parts
    final parts = <img.Image>[];
    for (var i = 0; i < count; i++) {
      for (var j = 0; j < count; j++) {
        parts.add(img.copyCrop(image, x, y, width, height));
        x += width;
      }
      x = 0;
      y += height;
    }

    // convert image from image package to Image Widget to display
    final output = <Uint8List>[];
    for (final part in parts) {
      output.add(Uint8List.fromList(img.encodeJpg(part)));
    }
    return output;
  }

  /// Build a list of tiles - giving each tile their correct position and a
  /// current position.
  List<Tile> _getTileListFromPositions(
    int size,
    List<Uint8List> scatterBytes,
    List<Position> correctPositions,
    List<Position> currentPositions,
  ) {
    final whitespacePosition = Position(x: size, y: size);
    return [
      for (int i = 1; i <= size * size; i++)
        if (i == size * size)
          Tile(
            value: i,
            bytes: scatterBytes[size],
            correctPosition: whitespacePosition,
            currentPosition: currentPositions[i - 1],
            isWhitespace: true,
          )
        else
          Tile(
            value: i,
            bytes: scatterBytes[i - 1],
            correctPosition: correctPositions[i - 1],
            currentPosition: currentPositions[i - 1],
          )
    ];
  }
}
