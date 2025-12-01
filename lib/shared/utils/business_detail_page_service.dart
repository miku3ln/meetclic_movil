import 'package:meetclic_movil/domain/models/api_response_model.dart';
import 'package:meetclic_movil/domain/models/business_model.dart';
import 'package:meetclic_movil/domain/usecases/get_nearby_businesses_usecase.dart';
import 'package:meetclic_movil/infrastructure/repositories/implementations/business_repository_impl.dart';

Future<ApiResponseModel<List<BusinessModel>>> _loadBusinessesDetails(
  businessId,
) async {
  final useCase = BusinessesDetailsUseCase(
    repository: BusinessDetailsRepositoryImpl(),
  );

  final response = await useCase.execute(businessId: businessId);
  return response;
}
