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
      print('[REGISTER] 🔐 Registrando con Supabase Auth: $email');

      // ✅ REGISTRAR CON SUPABASE AUTH primero
      final authResponse = await _supabase.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (authResponse.user == null) {
        throw Exception('No se pudo crear el usuario en Supabase Auth');
      }

      print('[REGISTER] ✅ Usuario creado en Supabase Auth: ${authResponse.user!.id}');

      // Verificar si ya existe perfil
      final existingUser = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_auth_email', email.trim().toLowerCase())
          .maybeSingle();
      
      if (existingUser != null) {
        print('[REGISTER] ℹ️ Perfil ya existe, usando existente');
        return UserLogin(
          userLoginId: existingUser['user_profile_id'].toString(),
          email: existingUser['user_auth_email'],
          password: password,
          fingerprintEnabled: fingerprintEnabled,
        );
      }

      // Crear nuevo usuario en user_profiles vinculado al auth user
      final response = await _supabase
          .from('user_profiles')
          .insert({
            'user_auth_email': authResponse.user!.email,
          })
          .select()
          .single();

      print('[REGISTER] ✅ Perfil creado en user_profiles: ${response['user_profile_id']}');

      return UserLogin(
        userLoginId: response['user_profile_id'].toString(),
        email: response['user_auth_email'],
        password: password,
        fingerprintEnabled: fingerprintEnabled,
      );
    } catch (e) {
      print('❌ Error en registro: $e');
      throw Exception('Error al registrar usuario: $e');
    }
  }

  @override
  Future<UserLogin> loginWithPassword({required String email, required String password}) async {
    try {
      final trimmed = email.trim();
      final lowered = trimmed.toLowerCase();
      print('[LOGIN] 🔐 Intentando login con Supabase Auth: $lowered');

      // ✅ USAR SUPABASE AUTH para crear una sesión autenticada
      final authResponse = await _supabase.auth.signInWithPassword(
        email: lowered,
        password: password,
      );

      if (authResponse.user == null) {
        throw Exception('No se pudo autenticar el usuario');
      }

      print('[LOGIN] ✅ Usuario autenticado con Supabase: ${authResponse.user!.id}');
      print('[LOGIN] 🔑 Email autenticado: ${authResponse.user!.email}');

      // Buscar el perfil correspondiente en user_profiles
      var response = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_auth_email', lowered)
          .maybeSingle();

      // Si no hay perfil, intentar con email exacto del auth
      if (response == null && authResponse.user!.email != null) {
        response = await _supabase
            .from('user_profiles')
            .select()
            .eq('user_auth_email', authResponse.user!.email!)
            .maybeSingle();
      }

      if (response == null) {
        print('[LOGIN] ⚠️ Usuario autenticado pero sin perfil en user_profiles');
        // Crear perfil automáticamente si no existe
        response = await _supabase
            .from('user_profiles')
            .insert({
              'user_auth_email': authResponse.user!.email,
            })
            .select()
            .single();
        print('[LOGIN] ✅ Perfil creado: ${response['user_profile_id']}');
      }

      return UserLogin(
        userLoginId: response['user_profile_id'].toString(),
        email: response['user_auth_email'],
        password: password,
        fingerprintEnabled: false,
      );
    } catch (e) {
      print('❌ Error en login: $e');
      throw Exception('Error al iniciar sesión: $e');
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