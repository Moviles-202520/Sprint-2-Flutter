import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/user_login.dart';

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  Future<UserLogin> register({
    required String email,
    required String password,
    bool fingerprintEnabled = false,
  }) async {
    try {
      // Primero verificar si el usuario ya existe
      final existingUser = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_auth_email', email)
          .maybeSingle();
      
      if (existingUser != null) {
        throw Exception('El correo ya está registrado');
      }

      // Crear nuevo usuario en user_profiles
      final response = await _supabase
          .from('user_profiles')
          .insert({
            'user_auth_email': email,
            // En un entorno real, hashearias la contraseña
          })
          .select()
          .single();

      return UserLogin(
        userLoginId: response['user_profile_id'].toString(),
        email: response['user_auth_email'],
        password: password,
        fingerprintEnabled: fingerprintEnabled,
      );
    } catch (e) {
      print('❌ Error en registro: $e');
      throw Exception('Error al registrar usuario');
    }
  }

  @override
  Future<UserLogin> loginWithPassword({required String email, required String password}) async {
    try {
      final raw = email;
      final trimmed = raw.trim();
      final lowered = trimmed.toLowerCase();
      print('[LOGIN] Email recibido: "$raw" -> trimmed: "$trimmed" -> lowered: "$lowered"');

      // 1) Intento exacto con el valor tal cual (trimmed)
      print('[LOGIN] Intentando búsqueda exacta (trimmed)...');
      var response = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_auth_email', trimmed)
          .maybeSingle();
      print('[LOGIN] Resultado exacto: $response');

      // 2) Si no encontré nada, intento con lowercase (por si en la BD está en otra forma)
      if (response == null && lowered != trimmed) {
        print('[LOGIN] Intentando búsqueda exacta (lowercase)...');
        response = await _supabase
            .from('user_profiles')
            .select()
            .eq('user_auth_email', lowered)
            .maybeSingle();
        print('[LOGIN] Resultado lowercase: $response');
      }

      // 3) Si aún no hay resultado, intento una búsqueda ilike (case-insensitive, permite coincidencias parciales)
      if (response == null) {
        print('[LOGIN] Intentando búsqueda ilike (contiene)...');
        response = await _supabase
            .from('user_profiles')
            .select()
            .ilike('user_auth_email', '%$trimmed%')
            .limit(1)
            .maybeSingle();
        print('[LOGIN] Resultado ilike: $response');
      }

      if (response == null) {
        print('[LOGIN] No se encontró usuario tras todos los intentos');
        throw Exception('Usuario no encontrado');
      }

      // Por ahora aceptamos cualquier contraseña
      return UserLogin(
        userLoginId: response['user_profile_id'].toString(),
        email: response['user_auth_email'],
        password: password,
        fingerprintEnabled: false,
      );
    } catch (e) {
      print('❌ Error en login: $e');
      throw Exception('Error al iniciar sesión');
    }
  }

  @override
  Future<bool> refreshSession() async {
    // Por ahora deshabilitamos el login biométrico
    return false;
  }

  @override
  Future<void> logout() async {
    // Por ahora solo limpiamos la sesión local
    await _supabase.auth.signOut();
  }
}