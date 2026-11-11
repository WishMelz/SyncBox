import { Transform } from 'class-transformer';
import { IsString, Length, Matches, IsOptional } from 'class-validator';
export class SetupDto {
  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toLowerCase() : value))
  @IsString()
  @Length(1, 254)
  @Matches(/^[^\s\u0000-\u001f\u007f]+$/)
  username!: string;
  @IsString() @Length(6, 128) password!: string;
}
export class LoginDto extends SetupDto {
  @IsOptional() @IsString() @Length(6, 40) code?: string;
}
