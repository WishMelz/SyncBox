import { Transform, Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsUUID,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class CreateMessageDto {
  @IsOptional() @IsUUID() clientId?: string;
  @Transform(trim) @IsString() @Length(1, 200) title!: string;
  @Transform(trim) @IsString() @Length(1, 50000) content!: string;
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(trim)
  @IsString()
  @Length(1, 80)
  source: string = 'manual';
}
export class ListMessagesDto {
  @Type(() => Number) @IsInt() @Min(1) @Max(1000000) page: number = 1;
  @Type(() => Number) @IsInt() @Min(1) @Max(100) pageSize: number = 20;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(200) q?: string;
  @IsOptional() @IsIn(['true', 'false']) isRead?: string;
  @IsOptional() @IsIn(['true', 'false']) isStarred?: string;
  @IsOptional() @Transform(trim) @IsString() @Length(1, 80) source?: string;
  @IsOptional() @IsString() @Length(1, 100) before?: string;
  @IsOptional() @IsString() @Length(1, 100) since?: string;
}
export class ListFilesDto {
  @Type(() => Number) @IsInt() @Min(1) @Max(1000000) page: number = 1;
  @Type(() => Number) @IsInt() @Min(1) @Max(100) pageSize: number = 30;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(200) q?: string;
  @IsOptional() @IsIn(['image', 'attachment']) kind?: 'image' | 'attachment';
}
export class UpdateMessageDto {
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(trim)
  @IsString()
  @MaxLength(2000)
  annotation?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @Transform(trim)
  @IsString()
  @Length(1, 200)
  title?: string;
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(trim)
  @IsString()
  @Length(1, 50000)
  content?: string;
  @ValidateIf((_object, value) => value !== undefined) @IsBoolean() isRead?: boolean;
  @ValidateIf((_object, value) => value !== undefined) @IsBoolean() isStarred?: boolean;
}
