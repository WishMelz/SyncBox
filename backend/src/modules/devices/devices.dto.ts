import { Transform } from 'class-transformer';
import { IsIn, IsString, IsUUID, Length, ValidateIf } from 'class-validator';
export class RegisterDeviceDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn(['fingerprint'])
  identityMode?: 'fingerprint';
  @ValidateIf((_object, value) => value !== undefined) @IsUUID() installationId?: string;
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @Length(1, 1024)
  fingerprint?: string;
  @ValidateIf((_object, value) => value !== undefined) @IsUUID() id?: string;
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 80)
  name!: string;
  @IsIn(['ios', 'ipados', 'macos', 'web', 'android', 'windows', 'linux', 'other'])
  platform!: string;
}
