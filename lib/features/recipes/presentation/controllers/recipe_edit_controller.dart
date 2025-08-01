import 'package:flutter/material.dart';
import 'package:intelligent_nutrition_app/features/recipes/data/models/models.dart';
import 'package:intelligent_nutrition_app/features/recipes/data/services/services.dart';
import 'package:intelligent_nutrition_app/core/services/database_helper.dart';
import 'package:intelligent_nutrition_app/core/utils/utils.dart';

// Define a specific exception for this business rule.
class RecipeExistsException implements Exception {
  final String message;
  RecipeExistsException(this.message);
}

class RecipeEditController with ChangeNotifier {
  final Recipe? _initialRecipe;
  final int? parentRecipeId;
  final _db = DatabaseHelper.instance;

  // State
  late TextEditingController titleController;
  late TextEditingController descriptionController;
  late TextEditingController prepTimeController;
  late TextEditingController cookTimeController;
  late TextEditingController totalTimeController;
  late TextEditingController servingsController;

  late List<Ingredient> ingredients;
  late List<String> instructions;
  late List<TimingInfo> otherTimings;
  late String sourceUrl;

  bool isDirty = false;
  bool isAnalyzing = false;

  late List<String> tags;

  RecipeEditController(this._initialRecipe, {this.parentRecipeId}) {
    // Initialize all state from the initial recipe or with default values
    _populateState(_initialRecipe);
    _addListeners();
  }

  void _populateState(Recipe? recipe) {
    titleController = TextEditingController(text: recipe?.title ?? '');
    descriptionController = TextEditingController(text: recipe?.description ?? '');
    prepTimeController = TextEditingController(text: recipe?.prepTime ?? '');
    cookTimeController = TextEditingController(text: recipe?.cookTime ?? '');
    totalTimeController = TextEditingController(text: recipe?.totalTime ?? '');
    servingsController = TextEditingController(text: recipe?.servings ?? '');
    ingredients = List<Ingredient>.from(recipe?.ingredients ?? []);
    instructions = List<String>.from(recipe?.instructions ?? []);
    otherTimings = List<TimingInfo>.from(recipe?.otherTimings ?? []);
    sourceUrl = recipe?.sourceUrl ?? '';

    // --- POPULATE TAGS ---
    tags = List<String>.from(recipe?.tags ?? []);

    notifyListeners();
  }

  void _addListeners() {
    titleController.addListener(_markDirty);
    descriptionController.addListener(_markDirty);
    prepTimeController.addListener(_markDirty);
    cookTimeController.addListener(_markDirty);
    totalTimeController.addListener(_markDirty);
    servingsController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!isDirty) {
      isDirty = true;
      notifyListeners();
    }
  }

  // --- List Management Methods ---
  void addIngredient(Ingredient newIngredient) {
    ingredients.add(newIngredient);
    _markDirty();
    notifyListeners();
  }

  void editIngredient(int index, Ingredient updatedIngredient) {
    ingredients[index] = updatedIngredient;
    _markDirty();
    notifyListeners();
  }

  void removeIngredient(int index) {
    ingredients.removeAt(index);
    _markDirty();
    notifyListeners();
  }

  void addInstruction() {
    instructions.add('New Step'); // Add a placeholder
    _markDirty();
    notifyListeners();
  }

  void editInstruction(int index, String updatedInstruction) {
    instructions[index] = updatedInstruction;
    _markDirty();
    notifyListeners();
  }

  void removeInstruction(int index) {
    instructions.removeAt(index);
    _markDirty();
    notifyListeners();
  }

  void addOtherTiming(TimingInfo newTiming) {
    otherTimings.add(newTiming);
    _markDirty();
    notifyListeners();
  }

  void editOtherTiming(int index, TimingInfo updatedTiming) {
    otherTimings[index] = updatedTiming;
    _markDirty();
    notifyListeners();
  }

  void removeOtherTiming(int index) {
    otherTimings.removeAt(index);
    _markDirty();
    notifyListeners();
  }

  // --- AI and Saving Logic ---
  Future<void> analyzePastedText(String text) async {
    if (text.isEmpty) return;
    isAnalyzing = true;
    notifyListeners();

    try {
      final recipe = await RecipeParsingService.analyzeText(text);
      _populateState(recipe); // Repopulate all fields with AI data
      _markDirty();
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }
  
  void updateTags(List<String> newTags) {
    tags = newTags;
    _markDirty();
    notifyListeners();
  }

  /// Saves the form data to the database.
  /// Throws a [RecipeExistsException] if a duplicate is found.
  Future<bool> saveForm() async {
    final newRecipe = Recipe(
      id: _initialRecipe?.id,
      parentRecipeId: parentRecipeId,
      title: titleController.text,
      description: descriptionController.text,
      prepTime: prepTimeController.text,
      cookTime: cookTimeController.text,
      totalTime: totalTimeController.text,
      servings: servingsController.text,
      ingredients: ingredients,
      instructions: instructions,
      otherTimings: otherTimings,
      sourceUrl: sourceUrl,
      // --- THIS IS THE FIX ---
      // You must include the tags from the controller's state
      // when building the new recipe object to be saved.
      tags: tags,
    );

    final fingerprint = FingerprintHelper.generate(newRecipe);

    // Only check for duplicates if it's a new recipe
    if (newRecipe.id == null) {
      final bool exists = await _db.doesRecipeExist(fingerprint);
      if (exists) {
        throw RecipeExistsException("An identical recipe already exists in your library.");
      }
    }

    final recipeToSave = newRecipe.copyWith(fingerprint: fingerprint);

    try {
      if (recipeToSave.id != null) {
        // --- HANDLE UPDATE ---
        await _db.update(recipeToSave);
        // For an update, we also need to update the tags.
        await _db.addTagsToRecipe(recipeToSave.id!, recipeToSave.tags);
      } else {
        // --- HANDLE INSERT ---
        // 1. Insert the recipe and get its new ID.
        final newId = await _db.insert(recipeToSave);
        // 2. Use the new ID to save the associated tags.
        await _db.addTagsToRecipe(newId, recipeToSave.tags);
      }
      isDirty = false; // Mark as clean after a successful save
      notifyListeners();
      return true; // Indicate success
    } catch (e) {
      // In a real app, you might want to handle this error more gracefully
      debugPrint("Error saving recipe: $e");
      return false; // Indicate failure
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    prepTimeController.dispose();
    cookTimeController.dispose();
    totalTimeController.dispose();
    servingsController.dispose();
    super.dispose();
  }
}